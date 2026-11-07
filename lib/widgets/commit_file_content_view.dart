import 'dart:convert';

import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import '../l10n/l10n.dart';
import '../models/repository_state.dart';
import 'native_menu.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../app/gitlama_layout.dart';

/// Read-only, bounded preview of one file at an exact commit. A file that
/// is not UTF-8 text can still be shown as text on request.
class CommitFileContentView extends StatefulWidget {
  const CommitFileContentView({
    required this.bytes,
    this.failure,
    this.controller,
    this.matchLines = const {},
    this.currentLine,
    super.key,
  });

  final List<int>? bytes;
  final RepositoryFailureCode? failure;
  final ScrollController? controller;

  /// Zero-based lines holding a search match.
  final Set<int> matchLines;

  /// The zero-based line of the current search match.
  final int? currentLine;

  @override
  State<CommitFileContentView> createState() => _CommitFileContentViewState();
}

class _CommitFileContentViewState extends State<CommitFileContentView> {
  bool _forceText = false;

  @override
  void didUpdateWidget(covariant CommitFileContentView oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Another file is checked for text again.
    if (!identical(oldWidget.bytes, widget.bytes)) _forceText = false;
  }

  @override
  Widget build(BuildContext context) {
    final failure = widget.failure;
    final controller = widget.controller;
    final matchLines = widget.matchLines;
    final currentLine = widget.currentLine;
    if (failure != null) {
      return MeridianEmptyState(
        compact: true,
        icon: 'circle-alert',
        title: failure == RepositoryFailureCode.tooLarge
            ? context.l10n.historyTreeFileTooLarge
            : context.l10n.historyTreeFileFailed,
      );
    }
    final content = widget.bytes;
    if (content == null) {
      return MeridianEmptyState(
        compact: true,
        progress: true,
        title: context.l10n.loading,
      );
    }
    if (content.isEmpty) {
      return MeridianEmptyState(
        compact: true,
        title: context.l10n.historyTreeEmptyFile,
      );
    }
    String text;
    if (_forceText) {
      // NUL bytes become visible symbols instead of vanishing.
      text = utf8
          .decode(content, allowMalformed: true)
          .replaceAll('\u0000', '\u2400');
    } else {
      try {
        if (content.contains(0)) throw const FormatException('binary');
        text = utf8.decode(content);
      } on FormatException {
        return MeridianEmptyState(
          compact: true,
          title: context.l10n.historyTreeBinaryFile,
          action: MeridianButton(
            key: const ValueKey('commit-file-show-as-text'),
            label: context.l10n.showBinaryAsText,
            variant: MeridianButtonVariant.secondary,
            onPressed: () => setState(() => _forceText = true),
          ),
        );
      }
    }
    final lines = text.split('\n');
    if (lines.last.isEmpty) lines.removeLast();
    final tokens = context.meridian;
    final style = context.text.code.copyWith(color: tokens.colors.ink);
    return ListView.builder(
      key: const Key('commit-file-content'),
      controller: controller,
      itemCount: lines.length,
      itemExtent: GitLamaLayout.diffLineHeight,
      itemBuilder: (context, index) => Container(
        color: index == currentLine
            ? tokens.colors.accentSoft
            : matchLines.contains(index)
            ? tokens.colors.paneHover
            : null,
        padding: const EdgeInsetsDirectional.only(end: MeridianSpace.space6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              width: GitLamaLayout.diffGutterWidth,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(
                  end: MeridianSpace.space4,
                ),
                child: Text(
                  '${index + 1}',
                  textAlign: TextAlign.right,
                  style: context.text.codeSm.copyWith(
                    color: tokens.colors.inkMuted,
                  ),
                ),
              ),
            ),
            const SizedBox(width: GitLamaLayout.diffSignWidth),
            Expanded(
              child: SelectableText(
                contextMenuBuilder: nativeTextContextMenuBuilder,
                lines[index],
                style: style,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
