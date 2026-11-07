import 'package:flutter/material.dart';

import '../app/app_theme.dart';
import 'gitlama_ref_chip.dart';
import 'package:meridian_ui/meridian_ui.dart';
import '../app/gitlama_layout.dart';

/// The persistent action strip above a repository workflow's islands.
class GitLamaWorkflowHeader extends StatelessWidget {
  const GitLamaWorkflowHeader({
    required this.title,
    required this.exitLabel,
    required this.onExit,
    super.key,
    this.contextChips = const [],
    this.status,
    this.primaryAction,
    this.actions = const [],
  });

  final String title;
  final List<Widget> contextChips;
  final String? status;
  final Widget? primaryAction;
  final List<Widget> actions;
  final String exitLabel;
  final VoidCallback onExit;

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: context.colors.ground,
    child: SizedBox(
      height: GitLamaLayout.workflowHeaderHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: MeridianSpace.space3),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final showContext = constraints.maxWidth >= 700;
            return Row(
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: context.text.bodyStrong.copyWith(
                      color: context.colors.ink,
                    ),
                  ),
                ),
                if (showContext && contextChips.isNotEmpty) ...[
                  const SizedBox(width: MeridianSpace.space4),
                  ...contextChips,
                ],
                if (showContext && status != null) ...[
                  const SizedBox(width: MeridianSpace.space4),
                  Flexible(
                    child: Text(
                      status!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: context.text.caption.copyWith(
                        color: context.colors.inkMuted,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                ...actions,
                if (primaryAction != null) ...[
                  const SizedBox(width: MeridianSpace.space4),
                  primaryAction!,
                ],
                const SizedBox(width: MeridianSpace.space4),
                MeridianButton(
                  label: exitLabel,
                  variant: MeridianButtonVariant.quiet,
                  size: MeridianControlSize.small,
                  onPressed: onExit,
                ),
              ],
            );
          },
        ),
      ),
    ),
  );
}

/// Compact source-to-target context in mutation previews.
class GitLamaFlowStrip extends StatelessWidget {
  const GitLamaFlowStrip({
    required this.source,
    required this.target,
    super.key,
  });

  final String source;
  final String target;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.colors.paneAlt,
      borderRadius: BorderRadius.circular(context.meridian.radius.lg),
    ),
    child: Padding(
      padding: const EdgeInsets.all(MeridianSpace.space5),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: MeridianSpace.space4,
        runSpacing: MeridianSpace.space2,
        children: [
          GitLamaRefChip(name: source, kind: GitLamaRefKind.other),
          MeridianIcon(
            'arrow-right',
            size: MeridianIconSize.small,
            color: context.colors.inkMuted,
          ),
          GitLamaRefChip(name: target, kind: GitLamaRefKind.other),
        ],
      ),
    ),
  );
}
