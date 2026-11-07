import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../app/gitlama_layout.dart';

import '../app/app_theme.dart';
import '../l10n/l10n.dart';
import 'native_menu.dart';

/// A workflow preview: what will happen in words, with the exact commands
/// behind a collapsed details disclosure.
class GitLamaCommandPreviewContent extends StatelessWidget {
  const GitLamaCommandPreviewContent({
    required this.summary,
    required this.commandLines,
    this.external = false,
    super.key,
  });

  final String summary;
  final List<String> commandLines;

  /// The commands start another program rather than Git, so the disclosure
  /// is titled "Command details".
  final bool external;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    spacing: MeridianSpace.space4,
    children: [
      Text(
        summary,
        style: context.text.body.copyWith(color: context.colors.ink),
      ),
      GitCommandDetails(
        commands: commandLines,
        title: external ? context.l10n.commandDetails : null,
      ),
    ],
  );
}

/// The exact git commands a workflow runs, one per line, behind a collapsed
/// "Git command details" disclosure (or [title]). The commands are
/// selectable and scroll within a bounded height.
class GitCommandDetails extends StatelessWidget {
  const GitCommandDetails({required this.commands, this.title, super.key});

  final List<String> commands;
  final String? title;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return MeridianDisclosure(
      title: title ?? context.l10n.gitCommandDetails,
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxHeight: GitLamaLayout.commandDetailsMaxHeight,
        ),
        child: SingleChildScrollView(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: colors.paneAlt,
              borderRadius: BorderRadius.circular(context.meridian.radius.md),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: MeridianSpace.space5,
                vertical: MeridianSpace.space4,
              ),
              child: SelectableText(
                contextMenuBuilder: nativeTextContextMenuBuilder,
                commands.join('\n'),
                style: context.text.codeSm.copyWith(color: colors.ink),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
