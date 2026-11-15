import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_native_menus/meridian_native_menus.dart'
    show MeridianNativeMenus;

import 'support/native_menu_model.dart';

/// Widget tests have no OS menu server. Render the exact native menu model in a
/// test-only popup so existing workflow tests can select actions. Native channel
/// tests turn this off explicitly; this is never linked into the application.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  // GitLama is a desktop app: Flutter starts desktop builds in the
  // traditional highlight mode, which Meridian's hover highlights follow.
  // The default test platform starts in touch mode.
  // Plain unit tests run without a binding; leave them alone.
  bool widgetTest() => BindingBase.debugBindingType() != null;
  setUp(() {
    if (widgetTest()) {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.alwaysTraditional;
    }
  });
  tearDown(() {
    if (widgetTest()) {
      FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic;
    }
  });
  // GitLama is a desktop app: its menus are native on every platform it
  // ships for, so tests show them through the presenter below.
  MeridianNativeMenus.debugSupportedOverride = true;
  nativeMenuTestPresenter = (context, menu, position) async {
    MenuAction? selected;
    await showMeridianContextMenu(
      context,
      globalPosition: position,
      // This presenter draws the Meridian menu itself.
      usePresenter: false,
      entries: [
        for (final item in menu.children)
          if (item is MenuSeparator)
            const MeridianMenuDivider()
          else if (item is MenuAction)
            MeridianMenuItem(
              label: item.title ?? '',
              onSelected: item.attributes.disabled
                  ? null
                  : () => selected = item,
            ),
      ],
    );
    final chosen = selected;
    if (context.mounted && chosen != null) chosen.callback();
    return MenuResult(itemSelected: chosen != null);
  };
  await testMain();
}
