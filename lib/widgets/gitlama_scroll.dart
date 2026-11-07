import 'package:flutter/widgets.dart';
import 'package:meridian_ui/meridian_ui.dart';

/// Scrolls [controller] to [offset]: animated over `motion-layout` when the
/// target is less than one viewport away, otherwise a jump
/// (docs/design-system/specs/motion.md NM-44, NM-45, NM-76). Reduce motion
/// always jumps.
Future<void> gitlamaScrollTo(
  ScrollController controller,
  double offset,
  BuildContext context,
) async {
  if (!controller.hasClients) return;
  final position = controller.position;
  final target = offset.clamp(
    position.minScrollExtent,
    position.maxScrollExtent,
  );
  final near =
      !position.hasViewportDimension ||
      (target - position.pixels).abs() < position.viewportDimension;
  final duration = MeridianMotion.of(context, MeridianDurations.layout);
  if (!near || duration == Duration.zero) {
    controller.jumpTo(target);
    return;
  }
  await controller.animateTo(
    target,
    duration: duration,
    curve: MeridianMotion.curve(context, MeridianDurations.layoutCurve),
  );
}

/// The scroll offset that reveals the row at [index] of a list of
/// [extent]-tall rows, or null when the row is already fully in view. A row
/// out of view is centred, so the rows around it are visible too.
/// [leadingPadding] is the list's padding above its first row.
double? gitlamaRevealOffset({
  required int index,
  required double extent,
  required double pixels,
  required double viewportDimension,
  double leadingPadding = 0,
}) {
  final top = leadingPadding + index * extent;
  if (top >= pixels && top + extent <= pixels + viewportDimension) {
    return null;
  }
  return top - (viewportDimension - extent) / 2;
}
