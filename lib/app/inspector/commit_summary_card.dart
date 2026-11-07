import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../../l10n/l10n.dart';
import '../../models/inspection.dart';
import '../../models/inspector.dart';
import '../../models/reference_name.dart';
import '../../widgets/author_avatar.dart';
import '../../widgets/gitlama_ref_chip.dart';
import '../../widgets/native_menu.dart';
import '../app_theme.dart';

/// The subject, author, date, hash, parents and refs of a commit, with its
/// message body and committer behind a disclosure.
///
/// Give it a bounded height: a long message then scrolls inside the card
/// instead of pushing the files and diff below it out of view.
class CommitSummaryCard extends StatefulWidget {
  const CommitSummaryCard({
    required this.detail,
    required this.onSelectParent,
    this.onSaveArchive,
    this.refs = const [],
    super.key,
  });

  final CommitIdentityDetail detail;

  /// Full ref names pointing at the commit, such as `refs/heads/main`.
  final List<String> refs;
  final ValueChanged<String> onSelectParent;

  /// Saves the commit's zip snapshot; the button is hidden without it.
  final VoidCallback? onSaveArchive;

  @override
  State<CommitSummaryCard> createState() => _CommitSummaryCardState();
}

class _CommitSummaryCardState extends State<CommitSummaryCard> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final detail = widget.detail;
    final refs = widget.refs;
    final onSelectParent = widget.onSelectParent;
    final message = utf8.decode(detail.message, allowMalformed: true).trim();
    final lines = message.split('\n');
    final subject = lines.firstOrNull ?? '';
    final body = lines.skip(1).join('\n').trim();
    final author = utf8.decode(detail.author, allowMalformed: true);
    final committer = utf8.decode(detail.committer, allowMalformed: true);
    final coauthors = RegExp(
      r'^Co-authored-by:\s*(.+)$',
      multiLine: true,
      caseSensitive: false,
    ).allMatches(message).map((match) => match.group(1)!).join(', ');
    final authored = DateTime.fromMillisecondsSinceEpoch(
      detail.authorTime * 1000,
    ).toLocal();
    final committed = DateTime.fromMillisecondsSinceEpoch(
      detail.committerTime * 1000,
    ).toLocal();
    final dates = MaterialLocalizations.of(context);
    final authorDate =
        '${dates.formatMediumDate(authored)} · ${dates.formatTimeOfDay(TimeOfDay.fromDateTime(authored))}';
    final commitDate =
        '${dates.formatMediumDate(committed)} · ${dates.formatTimeOfDay(TimeOfDay.fromDateTime(committed))}';
    final tokens = context.meridian;
    return ColoredBox(
      color: tokens.colors.pane,
      child: MeridianScrollbar(
        controller: _scroll,
        child: SingleChildScrollView(
          key: const ValueKey('commit-summary-scroll'),
          controller: _scroll,
          padding: const EdgeInsets.all(MeridianSpace.space5),
          child: MeridianDisclosure(
            key: ValueKey('commit-summary-${detail.commit}'),
            title: subject,
            header: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subject,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: context.text.heading.copyWith(
                    color: tokens.colors.ink,
                  ),
                ),
                const SizedBox(height: MeridianSpace.space3),
                Wrap(
                  spacing: MeridianSpace.space4,
                  runSpacing: MeridianSpace.space2,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AuthorAvatar(
                      author: author,
                      avatarHash: detail.avatarHash,
                      size: MeridianLayout.avatarSmall,
                    ),
                    Text(
                      author,
                      style: context.text.metaStrong.copyWith(
                        color: tokens.colors.ink,
                      ),
                    ),
                    Text(
                      authorDate,
                      style: context.text.label.copyWith(
                        color: tokens.colors.inkMuted,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.colors.paneAlt,
                        border: Border.all(color: tokens.colors.line),
                        borderRadius: BorderRadius.circular(
                          context.meridian.radius.sm,
                        ),
                      ),
                      child: Text(
                        shortObjectId(detail.commit),
                        style: context.text.codeSm.copyWith(
                          color: tokens.colors.inkMuted,
                        ),
                      ),
                    ),
                    for (final parent in detail.parents)
                      Tooltip(
                        message: parent,
                        child: MeridianInteraction(
                          onTap: () => onSelectParent(parent),
                          child: Text(
                            '← ${shortObjectId(parent)}',
                            style: context.text.codeSm.copyWith(
                              color: tokens.colors.accentInk,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (refs.isNotEmpty) ...[
                  const SizedBox(height: MeridianSpace.space3),
                  Wrap(
                    spacing: MeridianSpace.space2,
                    runSpacing: MeridianSpace.space2,
                    children: [
                      for (final ref in refs.map(ReferenceName.parse))
                        GitLamaRefChip(
                          name: ref.kind == ReferenceKind.stash
                              ? ref.fullText
                              : ref.display,
                          kind: switch (ref.kind) {
                            ReferenceKind.tag => GitLamaRefKind.tag,
                            ReferenceKind.remoteBranch => GitLamaRefKind.remote,
                            _ => GitLamaRefKind.local,
                          },
                        ),
                    ],
                  ),
                ],
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const MeridianHairline(),
                const SizedBox(height: MeridianSpace.space3),
                MeridianPropertyList(
                  properties: [
                    MeridianProperty(
                      label: context.l10n.historyAuthor,
                      value: author,
                    ),
                    if (coauthors.isNotEmpty)
                      MeridianProperty(
                        label: context.l10n.historyCoAuthors,
                        value: coauthors,
                      ),
                    if (committer != author)
                      MeridianProperty(
                        label: context.l10n.historyCommitter,
                        value: committer,
                      ),
                    if (commitDate != authorDate)
                      MeridianProperty(
                        label: context.l10n.historyCommitDate,
                        value: commitDate,
                      ),
                  ],
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: MeridianSpace.space5),
                  SelectableText(
                    contextMenuBuilder: nativeTextContextMenuBuilder,
                    body,
                    style: context.text.body.copyWith(
                      color: context.colors.ink,
                    ),
                  ),
                ],
                const SizedBox(height: MeridianSpace.space4),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        contextMenuBuilder: nativeTextContextMenuBuilder,
                        detail.commit,
                        style: context.text.codeSm.copyWith(
                          color: tokens.colors.inkMuted,
                        ),
                      ),
                    ),
                    if (widget.onSaveArchive case final onSaveArchive?)
                      MeridianIconButton(
                        key: const ValueKey('commit-summary-save-archive'),
                        label: context.l10n.commandSaveCommitArchive,
                        icon: 'archive',
                        onPressed: onSaveArchive,
                      ),
                    MeridianIconButton(
                      label: context.l10n.historyCopyObjectId,
                      icon: 'copy',
                      onPressed: () => unawaited(
                        Clipboard.setData(ClipboardData(text: detail.commit)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
