import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final local = overlay.globalToLocal(position);
    final selected = await showMenu<MenuAction>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(local.dx, local.dy, 0, 0),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final item in menu.children)
          if (item is MenuSeparator)
            const PopupMenuDivider()
          else if (item is MenuAction)
            PopupMenuItem(
              value: item,
              enabled: !item.attributes.disabled,
              child: Text(item.title ?? ''),
            ),
      ],
    );
    if (context.mounted && selected != null) selected.callback();
    return MenuResult(itemSelected: selected != null);
  };
  await testMain();
}
