import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/l10n.dart';
import '../../models/diff.dart';
import '../../models/inspection.dart';
import '../../models/inspector.dart';
import '../../services/inspector/inspector_service.dart';
import '../../services/inspector/lens_availability.dart';
import '../../widgets/git_file_list/git_file_list.dart';
import '../../widgets/gitlama_file_row.dart';
import '../app_theme.dart';
import '../file_actions/file_actions.dart';
import 'inspector_actions.dart';

/// The file list of an inspector: the target's changed files, or every file
/// of the commit as a lazily loaded tree.
class InspectorSidebar extends StatelessWidget {
  const InspectorSidebar({
    required this.state,
    required this.service,
    required this.actions,
    required this.mode,
    required this.onModeChanged,
    required this.onHide,
    required this.reveal,
    super.key,
  });

  final InspectorState state;
  final InspectorService service;
  final InspectorFileActions actions;
  final GitFileListMode mode;
  final ValueChanged<GitFileListMode> onModeChanged;
  final VoidCallback onHide;

  /// A folder of the Changed tree to expand.
  final ValueListenable<String?> reveal;

  InspectorLocation get _location => state.location!;

  /// Shows [path] with the current lens where it can, which the service
  /// replaces by a fallback otherwise.
  void _focus(List<int> path, {required bool replace}) {
    final location = _location.copyWith(
      path: path,
      directory: false,
      clearHistoryCommit: true,
      clearLines: true,
      anchor: 0,
    );
    unawaited(
      service.navigate(
        location,
        mode: replace
            ? InspectorNavigationMode.replace
            : InspectorNavigationMode.push,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final location = _location;
    final inspection = state.inspection;
    final comparison = location.target is ComparisonTarget;
    final rows = service.loadedDiffRows;
    final diff = state.diff;
    final complete =
        location.path == null &&
        diff != null &&
        rows.length == diff.diff.totalRows;
    final added = complete
        ? rows.values.where((row) => row.kind == DiffRowKind.addition).length
        : null;
    final deleted = complete
        ? rows.values.where((row) => row.kind == DiffRowKind.deletion).length
        : null;
    final all = location.scope == InspectorScope.all;
    return Column(
      children: [
        GitFileListHeader(
          title: all
              ? context.l10n.inspectorScopeAll
              : context.l10n.historyFilesCount(inspection?.files.length ?? 0),
          counts: [
            if (added != null)
              Text(
                '+$added',
                style: context.text.codeSm.copyWith(
                  color: context.colors.success,
                ),
              ),
            if (deleted != null)
              Text(
                '−$deleted',
                style: context.text.codeSm.copyWith(color: context.git.deleted),
              ),
          ],
          scope: MeridianSegmented<InspectorScope>(
            key: const ValueKey('inspector-scope'),
            label: context.l10n.inspectorScope,
            segments: [
              MeridianSegment(
                value: InspectorScope.changed,
                label: context.l10n.historyChangedFilesShort,
              ),
              MeridianSegment(
                value: InspectorScope.all,
                label: context.l10n.inspectorScopeAll,
                enabled: !comparison,
                tooltip: comparison
                    ? context.l10n.inspectorScopeAllUnavailable
                    : null,
              ),
            ],
            value: location.scope,
            size: MeridianControlSize.small,
            onChanged: (scope) {
              if (scope == location.scope) return;
              unawaited(service.navigate(location.copyWith(scope: scope)));
            },
          ),
          compactScope: MeridianIconButton(
            key: const ValueKey('inspector-scope-compact'),
            label: all
                ? context.l10n.historyChangedFilesShort
                : context.l10n.inspectorScopeAll,
            disabledReason: comparison
                ? context.l10n.inspectorScopeAllUnavailable
                : null,
            icon: all ? 'list-view' : 'tree-view',
            size: MeridianControlSize.small,
            onPressed: comparison && !all
                ? null
                : () => unawaited(
                    service.navigate(
                      location.copyWith(
                        scope: all
                            ? InspectorScope.changed
                            : InspectorScope.all,
                      ),
                    ),
                  ),
          ),
          mode: all ? null : mode,
          onModeChanged: all ? null : onModeChanged,
          modeKey: const ValueKey('commit-files-mode'),
        ),
        Expanded(
          child: all
              ? _AllFiles(
                  state: state,
                  service: service,
                  actions: actions,
                  onFocus: _focus,
                )
              : _changed(context),
        ),
      ],
    );
  }

  Widget _changed(BuildContext context) {
    final location = _location;
    final files = state.inspection?.files ?? const <CommitFileChange>[];
    final tooLarge = service.allChangesTooLarge;
    return GitFileList<CommitFileChange>(
      key: ValueKey('changed:${location.target.commit}'),
      listKey: const ValueKey('commit-files-list'),
      items: files,
      displayPath: (file) =>
          utf8.decode(changeDisplayPath(file), allowMalformed: true),
      mode: mode,
      reveal: reveal,
      folderKey: (identity) => ValueKey('commit-file-directory-$identity'),
      folderBuilder: (context, row, folder) => fileActionContextMenu(
        context: context,
        subject: () => FileActionSubject(
          source: FileActionSource.folder,
          path: utf8.encode(row.identity),
          changedFolder: true,
          revision: location.target.commit,
        ),
        host: actions,
        child: folder,
      ),
      leadingRows: [
        MeridianListRow(
          key: const ValueKey('commit-files-all-changes'),
          title: context.l10n.historyAllChanges,
          leading: const MeridianIcon('file-diff'),
          selected: location.path == null,
          enabled: !tooLarge,
          meta: tooLarge ? context.l10n.historyAllChangesTooLarge : null,
          onTap: tooLarge
              ? null
              : () => unawaited(
                  service.navigate(location.copyWith(clearPath: true)),
                ),
        ),
      ],
      fileRowBuilder: (context, row) {
        final file = row.item!;
        final path = changeDisplayPath(file);
        final subject = changedFileSubject(file, location.target);
        return Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (focused) {
            if (focused &&
                FocusManager.instance.highlightMode ==
                    FocusHighlightMode.traditional &&
                !listEquals(location.path, path)) {
              _focus(path, replace: true);
            }
          },
          child: fileActionContextMenu(
            context: context,
            subject: () => subject,
            host: actions,
            child: GitLamaFileRow(
              key: ValueKey(
                'commit-file-${utf8.decode(path, allowMalformed: true)}',
              ),
              status: commitFileCode(file.kind),
              path: row.label,
              depth: row.depth,
              selected: listEquals(location.path, path),
              trailing: FileActionButton(subject: () => subject, host: actions),
              onActivate: () {
                if (inspectionModifierPressed() &&
                    actions.host.supportsWindows) {
                  final shown = actions.locationFor(subject, location.lens);
                  if (shown != null) {
                    unawaited(actions.host.openInWindow(shown));
                  }
                  return;
                }
                _focus(path, replace: false);
              },
            ),
          ),
        );
      },
    );
  }
}

/// Every file of the target's commit, one folder read at a time.
class _AllFiles extends StatelessWidget {
  const _AllFiles({
    required this.state,
    required this.service,
    required this.actions,
    required this.onFocus,
  });

  final InspectorState state;
  final InspectorService service;
  final InspectorFileActions actions;
  final void Function(List<int> path, {required bool replace}) onFocus;

  @override
  Widget build(BuildContext context) {
    final location = state.location!;
    final changed = <String, CommitFileChange>{
      for (final file in state.inspection?.files ?? const <CommitFileChange>[])
        inspectorTreeKey(changeDisplayPath(file)): file,
    };
    final rows = <Widget>[];
    void add(List<int>? directory, int depth) {
      final folder = state.tree[inspectorTreeKey(directory)];
      if (folder == null) return;
      for (final entry in folder.entries) {
        final key = inspectorTreeKey(entry.path);
        final name = inspectorFileName(entry.path);
        if (entry.kind == CommitTreeEntryKind.directory) {
          final expanded = state.expanded.contains(key);
          final loaded = state.tree[key];
          rows.add(
            fileActionContextMenu(
              context: context,
              subject: () => FileActionSubject(
                source: FileActionSource.folder,
                path: entry.path,
                revision: location.target.commit,
              ),
              host: actions,
              child: GitFolderRow(
                key: ValueKey('tree-directory-$key'),
                label: name,
                depth: depth,
                collapsed: !expanded,
                loading: expanded && (loaded?.loading ?? false),
                onToggle: () => expanded
                    ? service.collapseDirectory(entry.path)
                    : unawaited(service.expandDirectory(entry.path)),
              ),
            ),
          );
          if (expanded) add(entry.path, depth + 1);
          continue;
        }
        final change = changed[key];
        final subject = change == null
            ? FileActionSubject(
                source: FileActionSource.treeFile,
                path: entry.path,
                treeKind: entry.kind,
                mode: entry.mode,
                revision: location.target.commit,
              )
            : changedFileSubject(change, location.target);
        rows.add(
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onFocusChange: (focused) {
              if (focused &&
                  FocusManager.instance.highlightMode ==
                      FocusHighlightMode.traditional &&
                  !listEquals(location.path, entry.path)) {
                onFocus(entry.path, replace: true);
              }
            },
            child: fileActionContextMenu(
              context: context,
              subject: () => subject,
              host: actions,
              child: GitLamaFileRow(
                key: ValueKey('tree-file-$key'),
                status: change == null ? '' : commitFileCode(change.kind),
                path: name,
                depth: depth,
                selected: listEquals(location.path, entry.path),
                trailing: FileActionButton(
                  subject: () => subject,
                  host: actions,
                ),
                onActivate: () => onFocus(entry.path, replace: false),
              ),
            ),
          ),
        );
      }
      if (folder.failed) {
        rows.add(
          MeridianListRow(
            title: context.l10n.retry,
            leading: Padding(
              padding: EdgeInsetsDirectional.only(
                start: depth * MeridianLayout.treeIndent,
              ),
              child: const MeridianIcon('rotate-ccw'),
            ),
            onTap: () => unawaited(service.expandDirectory(directory)),
          ),
        );
      } else if (folder.nextOffset != null) {
        rows.add(
          MeridianListRow(
            title: context.l10n.inspectorLoadMoreFiles,
            leading: Padding(
              padding: EdgeInsetsDirectional.only(
                start: depth * MeridianLayout.treeIndent,
              ),
              child: const MeridianIcon('more'),
            ),
            onTap: folder.loading
                ? null
                : () => unawaited(service.loadMoreDirectory(directory)),
          ),
        );
      }
    }

    add(null, 0);
    if (rows.isEmpty) {
      final root = state.tree[inspectorTreeKey(null)];
      return Center(
        child: root == null || root.loading
            ? const MeridianSpinner()
            : Text(context.l10n.inspectorNoFiles),
      );
    }
    return ListView.builder(
      key: const ValueKey('inspector-all-files'),
      itemCount: rows.length,
      itemExtent: context.meridian.density.rowExtent,
      itemBuilder: (context, index) => rows[index],
    );
  }
}
