import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/l10n.dart';
import '../../models/app_command.dart';
import '../../models/app_shortcut.dart';
import '../../models/diff_renderer.dart';
import '../../models/inspection.dart';
import '../../models/inspector.dart';
import '../../services/inspector/inspector_service.dart';
import '../../services/inspector/lens_availability.dart';
import '../../widgets/author_avatar.dart';
import '../../widgets/git_file_list/git_file_list.dart';
import '../../widgets/gitlama_file_row.dart';
import '../app_theme.dart';
import '../file_actions/file_actions.dart';
import 'commit_diff_pane.dart';
import 'inspector_actions.dart';
import 'inspector_host.dart';

/// One commit of a path's history, from a path or a line-range history.
final class _Entry {
  const _Entry({
    required this.commit,
    required this.summary,
    required this.author,
    required this.authorTime,
    this.oldPath,
  });

  final String commit;
  final List<int> summary;
  final List<int> author;
  final int authorTime;
  final List<int>? oldPath;
}

List<_Entry> _entries(InspectorState state) => [
  if (state.rangeHistory case final range?)
    for (final entry in range.entries)
      _Entry(
        commit: entry.commit,
        summary: entry.summary,
        author: entry.author,
        authorTime: entry.authorTime,
      )
  else
    for (final entry in state.history?.entries ?? const <PathHistoryEntry>[])
      _Entry(
        commit: entry.commit,
        summary: entry.summary,
        author: entry.author,
        authorTime: entry.authorTime,
        oldPath: entry.oldPath,
      ),
];

/// The commits that changed the focused path, in the sidebar's place.
class InspectorHistoryList extends StatelessWidget {
  const InspectorHistoryList({
    required this.state,
    required this.service,
    required this.host,
    super.key,
  });

  final InspectorState state;
  final InspectorService service;
  final InspectorHost host;

  @override
  Widget build(BuildContext context) {
    final location = state.location!;
    final lines = location.lines;
    final entries = _entries(state);
    final dates = MaterialLocalizations.of(context);
    final density = context.meridian.density;
    final extent =
        density.rowExtent +
        (density.isTouch
            ? MeridianLayout.rowTwoLineExtraTouch
            : MeridianLayout.rowTwoLineExtra);
    final page = state.history;
    final loaded = state.history != null || state.rangeHistory != null;
    final tail = lines != null || page?.nextOffset == null
        ? null
        : state.historyLoadingMore
        ? const Center(child: MeridianSpinner())
        : MeridianListRow(
            key: const ValueKey('inspector-history-more'),
            title: state.historyMoreFailed
                ? context.l10n.retry
                : context.l10n.inspectorLoadOlder,
            leading: MeridianIcon(
              state.historyMoreFailed ? 'rotate-ccw' : 'history',
            ),
            onTap: () => unawaited(service.loadMoreHistory()),
          );
    return Column(
      children: [
        GitFileListHeader(
          title: context.l10n.inspectorLensHistory,
          count: loaded ? entries.length : null,
          scope: lines == null
              ? null
              : MeridianChip(
                  key: const ValueKey('inspector-line-range'),
                  label: context.l10n.inspectorLines(lines.first, lines.last),
                  onRemove: () => unawaited(
                    service.navigate(
                      location.copyWith(
                        clearLines: true,
                        clearHistoryCommit: true,
                      ),
                    ),
                  ),
                  removeLabel: context.l10n.inspectorClearLines,
                ),
        ),
        Expanded(
          child: !loaded
              ? MeridianEmptyState(
                  compact: true,
                  progress: true,
                  title: context.l10n.loading,
                )
              : entries.isEmpty
              ? MeridianEmptyState(
                  compact: true,
                  title: context.l10n.inspectorNoHistory,
                )
              : Semantics(
                  label: context.l10n.inspectorHistoryOf(
                    utf8.decode(location.path!, allowMalformed: true),
                  ),
                  child: ListView.builder(
                    key: ValueKey(
                      'inspector-history:${location.target.commit}:'
                      '${location.path}:${location.lines?.first}',
                    ),
                    itemCount: entries.length + (tail == null ? 0 : 1),
                    itemExtent: extent,
                    itemBuilder: (context, index) {
                      if (index == entries.length) return tail!;
                      final entry = entries[index];
                      final author = utf8.decode(
                        entry.author,
                        allowMalformed: true,
                      );
                      final date = dates.formatMediumDate(
                        DateTime.fromMillisecondsSinceEpoch(
                          entry.authorTime * 1000,
                        ),
                      );
                      final rename = entry.oldPath == null
                          ? null
                          : context.l10n.historyRenamedFrom(
                              utf8.decode(entry.oldPath!, allowMalformed: true),
                            );
                      return MeridianListRow(
                        key: ValueKey('inspector-history-${entry.commit}'),
                        twoLine: true,
                        title: utf8.decode(entry.summary, allowMalformed: true),
                        leading: const MeridianIcon('history'),
                        subtitle: [author, date, ?rename].join(' · '),
                        trailing: Text(
                          shortObjectId(entry.commit),
                          style: context.text.codeSm.copyWith(
                            color: context.colors.inkMuted,
                          ),
                        ),
                        selected: entry.commit == location.historyCommit,
                        onTap: () =>
                            unawaited(service.selectHistoryEntry(entry.commit)),
                        onDoubleTap: () => unawaited(
                          inspectLocation(
                            service,
                            host,
                            InspectorLocation(
                              target: CommitTarget(entry.commit),
                              path: location.directory ? null : location.path,
                            ),
                            invert: false,
                          ),
                        ),
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }
}

/// The selected history entry: its commit and the change it made to the
/// path.
class InspectorHistoryDetail extends StatelessWidget {
  const InspectorHistoryDetail({
    required this.state,
    required this.service,
    required this.host,
    required this.actions,
    required this.shortcuts,
    required this.diffRenderer,
    super.key,
  });

  final InspectorState state;
  final InspectorService service;
  final InspectorHost host;
  final InspectorFileActions actions;
  final Map<AppCommandId, AppShortcut?> shortcuts;
  final DiffRendererDefinition? diffRenderer;

  @override
  Widget build(BuildContext context) {
    final location = state.location!;
    final commit = location.historyCommit;
    final entry = state.historyEntry;
    if (commit == null) {
      final loaded = state.history != null || state.rangeHistory != null;
      return Center(
        child: loaded
            ? Text(context.l10n.inspectorNoHistory)
            : const MeridianSpinner(),
      );
    }
    final tokens = context.meridian;
    final path = location.path!;
    final summary = entry == null
        ? ''
        : utf8
              .decode(entry.detail.message, allowMalformed: true)
              .trim()
              .split('\n')
              .first;
    final author = entry == null
        ? ''
        : utf8.decode(entry.detail.author, allowMalformed: true);
    final dates = MaterialLocalizations.of(context);
    final time = entry == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            entry.detail.authorTime * 1000,
          ).toLocal();
    void open(InspectorLens lens) => unawaited(
      inspectLocation(
        service,
        host,
        InspectorLocation(
          target: CommitTarget(commit),
          path: location.directory ? null : path,
          lens: lens,
        ),
        invert: inspectionModifierPressed(),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ColoredBox(
          color: tokens.colors.pane,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: MeridianSpace.space5,
              vertical: MeridianSpace.space4,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.bodyStrong.copyWith(
                    color: tokens.colors.ink,
                  ),
                ),
                const SizedBox(height: MeridianSpace.space2),
                Wrap(
                  spacing: MeridianSpace.space3,
                  runSpacing: MeridianSpace.space2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (author.isNotEmpty) ...[
                      AuthorAvatar(
                        author: author,
                        avatarHash: entry!.detail.avatarHash,
                        size: MeridianLayout.avatarSmall,
                      ),
                      Text(
                        author,
                        style: context.text.metaStrong.copyWith(
                          color: tokens.colors.ink,
                        ),
                      ),
                    ],
                    if (time != null)
                      Text(
                        '${dates.formatMediumDate(time)} · '
                        '${dates.formatTimeOfDay(TimeOfDay.fromDateTime(time))}',
                        style: context.text.label.copyWith(
                          color: tokens.colors.inkMuted,
                        ),
                      ),
                    Text(
                      shortObjectId(commit),
                      style: context.text.codeSm.copyWith(
                        color: tokens.colors.inkMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: MeridianSpace.space3),
                Wrap(
                  spacing: MeridianSpace.space2,
                  runSpacing: MeridianSpace.space2,
                  children: [
                    MeridianButton(
                      key: const ValueKey('inspector-history-show-commit'),
                      label: context.l10n.inspectorShowCommit,
                      icon: 'git-commit-horizontal',
                      size: MeridianControlSize.small,
                      variant: MeridianButtonVariant.secondary,
                      onPressed: () => open(InspectorLens.diff),
                    ),
                    if (!location.directory) ...[
                      MeridianButton(
                        key: const ValueKey('inspector-history-blame'),
                        label: context.l10n.inspectorBlameAtCommit,
                        icon: 'blame',
                        size: MeridianControlSize.small,
                        variant: MeridianButtonVariant.quiet,
                        onPressed: () => open(InspectorLens.blame),
                      ),
                      MeridianButton(
                        key: const ValueKey('inspector-history-contents'),
                        label: context.l10n.inspectorLensContents,
                        icon: 'file-text',
                        size: MeridianControlSize.small,
                        variant: MeridianButtonVariant.quiet,
                        onPressed: () => open(InspectorLens.contents),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
        const MeridianHairline(),
        Expanded(
          child: location.directory
              ? _folderFiles(context, path, commit)
              : state.diff == null
              ? MeridianEmptyState(
                  compact: true,
                  progress: true,
                  title: context.l10n.loading,
                )
              : CommitDiffPane(
                  detail: state.diff!,
                  service: service,
                  repositories: host.repositories,
                  diffRenderer: diffRenderer,
                  shortcuts: shortcuts,
                ),
        ),
      ],
    );
  }

  Widget _folderFiles(BuildContext context, List<int> folder, String commit) {
    final entry = state.historyEntry;
    if (entry == null) {
      return MeridianEmptyState(
        compact: true,
        progress: true,
        title: context.l10n.loading,
      );
    }
    final prefix = [...folder, 0x2f];
    final files = [
      for (final file in entry.files)
        if (_startsWith(changeDisplayPath(file), prefix)) file,
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(MeridianSpace.space4),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              context.l10n.inspectorChangedFilesIn(files.length),
              style: context.text.label.copyWith(
                color: context.colors.inkMuted,
              ),
            ),
          ),
        ),
        Expanded(
          child: GitFileList<CommitFileChange>(
            listKey: const ValueKey('inspector-history-files'),
            items: files,
            displayPath: (file) =>
                utf8.decode(changeDisplayPath(file), allowMalformed: true),
            mode: GitFileListMode.list,
            fileRowBuilder: (context, row) {
              final file = row.item!;
              final subject = FileActionSubject(
                source: FileActionSource.historyEntryFile,
                path: changeDisplayPath(file),
                oldPath: file.oldPath.isEmpty ? null : file.oldPath,
                changeKind: file.kind,
                mode: file.newMode,
                revision: commit,
              );
              return fileActionContextMenu(
                context: context,
                subject: () => subject,
                host: actions,
                child: GitLamaFileRow(
                  status: commitFileCode(file.kind),
                  path: row.label,
                  trailing: FileActionButton(
                    subject: () => subject,
                    host: actions,
                  ),
                  onActivate: () => unawaited(
                    inspectLocation(
                      service,
                      host,
                      InspectorLocation(
                        target: CommitTarget(commit),
                        path: changeDisplayPath(file),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

bool _startsWith(List<int> value, List<int> prefix) =>
    value.length >= prefix.length &&
    listEquals(value.sublist(0, prefix.length), prefix);
