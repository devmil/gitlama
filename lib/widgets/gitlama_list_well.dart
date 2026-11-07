import 'package:flutter/material.dart';
import 'package:meridian_ui/meridian_ui.dart';

import '../app/app_theme.dart';
import '../app/gitlama_layout.dart';

/// A bounded list of files, commits, branches or steps inside a dialog: a
/// `paneAlt` well (`radius.lg`) of [MeridianListRow]s that scrolls once it
/// reaches [maxHeight] (docs/design-system/components/Dialog.md).
class GitLamaListWell extends StatelessWidget {
  const GitLamaListWell({
    required this.itemCount,
    required this.itemBuilder,
    this.header,
    this.maxHeight = GitLamaLayout.dialogListMaxHeight,
    super.key,
  });

  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  /// Shown above the rows inside the well: a count, a Select all.
  final Widget? header;
  final double maxHeight;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.colors.paneAlt,
      borderRadius: BorderRadius.circular(context.meridian.radius.lg),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ?header,
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: MeridianList.builder(
            shrinkWrap: true,
            itemCount: itemCount,
            itemBuilder: itemBuilder,
          ),
        ),
      ],
    ),
  );
}

/// The position of a step in an ordered list (a restack or rebase plan),
/// in the slot a row's glyph takes.
class GitLamaStepNumber extends StatelessWidget {
  const GitLamaStepNumber(this.number, {super.key});

  final int number;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: GitLamaLayout.glyphSize),
    child: Text(
      '$number',
      textAlign: TextAlign.end,
      style: context.text.codeSm.copyWith(color: context.colors.inkMuted),
    ),
  );
}

/// A file in a dialog list: its name, then its folder, muted.
MeridianListRow gitLamaPathRow(
  String path, {
  Widget? leading,
  bool? checked,
  VoidCallback? onTap,
  Key? key,
}) {
  final slash = path.lastIndexOf('/');
  return MeridianListRow(
    key: key,
    checked: checked,
    leading: leading,
    title: path.substring(slash + 1),
    subtitle: slash < 0 ? null : path.substring(0, slash),
    onTap: onTap,
  );
}
