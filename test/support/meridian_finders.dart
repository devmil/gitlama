import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_ui/meridian_ui.dart';

Finder findLucide(String name) => find.byWidgetPredicate(
  (widget) => widget is MeridianIcon && widget.name == name,
  description: 'Lucide icon $name',
);

/// A reference name as a chip shows it. The chip keeps both ends of a long
/// name, so [name] is the complete one, not the text on screen.
Finder findRefName(String name) => find.byWidgetPredicate(
  (widget) => widget is MeridianMiddleEllipsis && widget.text == name,
  description: 'reference name $name',
);

/// GitLama's Meridian text styles (desktop scale, light theme) for
/// size and weight expectations outside a widget tree.
final MeridianTextStyles gitlamaText = MeridianTheme.resolve(
  brand: MeridianBrands.gitlama,
  brightness: Brightness.light,
).text;

/// The height of a small labelled button at 100% text. Since Meridian 0.13.2
/// the density's small extent is a minimum: the button also fits its label
/// line plus `space-2` above and below, which at GitLama's 12/16 label is
/// taller than the regular density's 22 px.
final double gitlamaSmallButtonHeight = math.max(
  MeridianSize.controlSm,
  gitlamaText.label.fontSize! * gitlamaText.label.height! +
      MeridianSpace.space2 * 2,
);

/// GitLama's corner radii (the standard Meridian scale).
const MeridianRadiusScale gitlamaRadius = MeridianRadiusScale.standard;
