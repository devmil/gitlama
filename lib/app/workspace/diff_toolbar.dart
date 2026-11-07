import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../widgets/native_menu.dart';
import '../../l10n/l10n.dart';
import '../../models/diff.dart';
import '../app_theme.dart';
import '../gitlama_layout.dart';
import 'package:meridian_ui/meridian_ui.dart';

/// One-line diff chrome. The pinned actions stay at the end; when the detail
/// pane narrows the path label goes first, then the action strip scrolls.
class DiffToolbar extends StatelessWidget {
  const DiffToolbar({
    required this.children,
    required this.path,
    this.leading,
    this.pinned = const [],
    super.key,
  });

  final List<Widget> children;
  final String path;

  /// Shown before the path, for leaving the scope the path names.
  final Widget? leading;

  /// Actions that stay visible while [children] scroll.
  final List<Widget> pinned;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final slash = path.lastIndexOf('/');
    final directory = slash < 0 ? '' : path.substring(0, slash + 1);
    final name = path.substring(slash + 1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final showPath =
            constraints.maxWidth >= GitLamaLayout.diffToolbarPathMinWidth;
        return MeridianSectionHeader(
          color: colors.pane,
          leading: leading,
          title: showPath ? path : null,
          titleChild: !showPath
              ? null
              : SizedBox(
                  width: math.min(
                    GitLamaLayout.diffToolbarPathMaxWidth,
                    math.max(
                      GitLamaLayout.diffToolbarPathMinLabelWidth,
                      constraints.maxWidth *
                          GitLamaLayout.diffToolbarPathWidthFraction,
                    ),
                  ),
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: directory,
                          style: context.text.label.copyWith(
                            color: colors.inkMuted,
                          ),
                        ),
                        TextSpan(
                          text: name,
                          style: context.text.label.copyWith(color: colors.ink),
                        ),
                      ],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
          middle: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(mainAxisSize: MainAxisSize.min, children: children),
          ),
          actions: pinned,
        );
      },
    );
  }
}

/// Viewing controls common to working-tree and committed diffs.
class DiffViewingActions {
  const DiffViewingActions({
    required this.options,
    required this.onOptionsChanged,
    required this.wrap,
    required this.onWrapChanged,
    required this.showIndicators,
    required this.onIndicatorsChanged,
    required this.showMinimap,
    this.minimapAvailable = true,
    required this.onMinimapChanged,
    required this.encoding,
    required this.onEncodingChanged,
  });

  final DiffLoadOptions options;
  final ValueChanged<DiffLoadOptions> onOptionsChanged;
  final bool wrap;
  final ValueChanged<bool> onWrapChanged;
  final bool showIndicators;
  final ValueChanged<bool> onIndicatorsChanged;
  final bool showMinimap;
  final bool minimapAvailable;
  final ValueChanged<bool> onMinimapChanged;
  final DiffTextEncoding encoding;
  final ValueChanged<DiffTextEncoding> onEncodingChanged;

  List<Widget> buttons(BuildContext context) => [
    MeridianIconButton(
      label: context.l10n.diffWrap,
      icon: 'wrap',
      active: wrap,
      size: MeridianControlSize.small,
      onPressed: () => onWrapChanged(!wrap),
    ),
    MeridianIconButton(
      label: context.l10n.diffWhitespace,
      icon: 'whitespace',
      size: MeridianControlSize.small,
      onPressed: () => onOptionsChanged(
        options.copyWith(
          whitespace:
              DiffWhitespace.values[(options.whitespace.index + 1) %
                  DiffWhitespace.values.length],
        ),
      ),
    ),
    NativeMenuButton<int>(
      tooltip: context.l10n.diffContextLines,
      initialValue: options.contextLines,
      onSelected: (value) =>
          onOptionsChanged(options.copyWith(contextLines: value)),
      itemBuilder: (context) => [
        for (final value in const [0, 3, 6, 10])
          NativeMenuItem(
            value: value,
            title: context.l10n.diffContextValue(value),
          ),
      ],
      icon: const MeridianIcon('chevrons-down-up'),
      constraints: const BoxConstraints.tightFor(
        width: MeridianSize.controlSm,
        height: MeridianSize.controlSm,
      ),
      padding: const EdgeInsets.all(MeridianSpace.space1),
    ),
    MeridianIconButton(
      label: context.l10n.diffMinimap,
      icon: 'map',
      active: showMinimap && minimapAvailable,
      size: MeridianControlSize.small,
      onPressed: minimapAvailable ? () => onMinimapChanged(!showMinimap) : null,
    ),
    NativeMenuButton<DiffTextEncoding>(
      key: const Key('diff-encoding'),
      tooltip: context.l10n.diffEncoding,
      initialValue: encoding,
      onSelected: onEncodingChanged,
      itemBuilder: (context) => [
        NativeMenuItem(
          value: DiffTextEncoding.utf8,
          title: context.l10n.diffEncodingUtf8,
        ),
        NativeMenuItem(
          value: DiffTextEncoding.latin1,
          title: context.l10n.diffEncodingLatin1,
        ),
      ],
      icon: const MeridianIcon('type'),
      constraints: const BoxConstraints.tightFor(
        width: MeridianSize.controlSm,
        height: MeridianSize.controlSm,
      ),
      padding: const EdgeInsets.all(MeridianSpace.space1),
    ),
    MeridianSegmented<DiffViewLayout>(
      label: context.l10n.galleryDiffLayout,
      segments: [
        for (final value in DiffViewLayout.values)
          MeridianSegment(
            value: value,
            icon: value == DiffViewLayout.unified
                ? 'unified-diff'
                : 'side-by-side',
            tooltip: value == DiffViewLayout.unified
                ? context.l10n.diffUnified
                : context.l10n.diffSideBySide,
          ),
      ],
      value: options.layout,
      onChanged: (value) => onOptionsChanged(options.copyWith(layout: value)),
      size: MeridianControlSize.small,
    ),
    MeridianIconButton(
      label: context.l10n.diffIndicators,
      icon: 'square-plus',
      active: showIndicators,
      size: MeridianControlSize.small,
      onPressed: () => onIndicatorsChanged(!showIndicators),
    ),
  ];
}
