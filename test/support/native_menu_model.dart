import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:gitlama/widgets/native_menu.dart';
import 'package:meridian_native_menus/meridian_native_menus.dart' as native;

/// A test's view of a native menu: the menu
/// `meridian_native_menus` would hand the operating system, as titled
/// elements a test can inspect and choose from. The names follow the menu
/// model the suite was written against.
sealed class MenuElement {
  const MenuElement();

  String? get title;
}

final class Menu extends MenuElement {
  const Menu({this.title, required this.children, this.icon});

  @override
  final String? title;
  final List<MenuElement> children;
  final String? icon;
}

final class MenuSeparator extends MenuElement {
  const MenuSeparator();

  @override
  String? get title => null;
}

enum MenuActionState { none, checkOn, checkOff }

final class MenuActionAttributes {
  const MenuActionAttributes({this.disabled = false, this.destructive = false});

  final bool disabled;
  final bool destructive;
}

final class MenuAction extends MenuElement {
  const MenuAction({
    required this.title,
    required this.callback,
    this.attributes = const MenuActionAttributes(),
    this.state = MenuActionState.none,
    this.icon,
    this.shortcut,
    this.header = false,
  });

  @override
  final String? title;

  /// Chooses the item: inside a test presenter it becomes the menu's
  /// answer; on a model from [ContextMenuModel.testMenu] it runs the item.
  final VoidCallback callback;
  final MenuActionAttributes attributes;
  final MenuActionState state;
  final String? icon;
  final native.NativeMenuShortcut? shortcut;

  /// A group title, which cannot be chosen.
  final bool header;
}

final class MenuResult {
  const MenuResult({required this.itemSelected});

  final bool itemSelected;
}

/// The view of [nodes]; [choose] says what choosing an action does.
Menu nativeMenuView(
  List<native.NativeMenuNode> nodes, {
  required VoidCallback Function(native.NativeMenuAction action) choose,
  String? title,
  String? icon,
}) => Menu(
  title: title,
  icon: icon,
  children: [
    for (final node in nodes)
      switch (node) {
        native.NativeMenuSeparator() => const MenuSeparator(),
        native.NativeMenuSubmenu() => nativeMenuView(
          node.children,
          choose: choose,
          title: node.title,
          icon: node.icon,
        ),
        native.NativeMenuAction() => MenuAction(
          title: node.title,
          callback: choose(node),
          attributes: MenuActionAttributes(
            disabled: !node.enabled || node.header,
            destructive: node.danger,
          ),
          state: switch (node.checked) {
            true => MenuActionState.checkOn,
            false => MenuActionState.checkOff,
            null => MenuActionState.none,
          },
          icon: node.icon,
          shortcut: node.shortcut,
          header: node.header,
        ),
      },
  ],
);

/// The view of self-running [items], whose actions run when chosen.
Menu nativeMenuFromActions(List<NativeMenuAction> items) => nativeMenuView(
  native.nativeMenuFromMeridian(meridianEntriesFromActions(items)),
  choose: (action) =>
      () => action.enabled && !action.header ? action.onSelected?.call() : null,
);

/// [menu] as a list of maps, the way a host would receive it.
List<Map<String, Object?>> encodeMenuForTest(Menu menu) => [
  for (final element in menu.children)
    switch (element) {
      MenuSeparator() => {'separator': true},
      Menu() => {'title': element.title, 'items': encodeMenuForTest(element)},
      MenuAction() => {
        'title': element.title,
        'enabled': !element.attributes.disabled,
        'checked': element.state == MenuActionState.checkOn,
        if (element.header) 'header': true,
        if (element.attributes.destructive) 'danger': true,
      },
    },
];

typedef TestMenuPresenter =
    Future<MenuResult> Function(BuildContext context, Menu menu, Offset at);

TestMenuPresenter? _presenter;

/// What shows native menus in widget tests. A presenter chooses an item by
/// calling its [MenuAction.callback] and answers whether it chose one; the
/// item's action then runs once the menu has closed, as on a desktop.
TestMenuPresenter? get nativeMenuTestPresenter => _presenter;

set nativeMenuTestPresenter(TestMenuPresenter? presenter) {
  _presenter = presenter;
  native.MeridianNativeMenus.debugShowOverride = presenter == null
      ? null
      : (context, nodes, position) async {
          int? chosen;
          var closed = false;
          final menu = nativeMenuView(
            nodes,
            // While the menu is open, choosing answers it; a test that keeps
            // the model and chooses later runs the item itself.
            choose: (action) => () {
              if (!closed) {
                chosen = action.id;
              } else if (action.enabled && !action.header) {
                action.onSelected?.call();
              }
            },
          );
          final result = await presenter(context, menu, position);
          closed = true;
          return result.itemSelected ? chosen : null;
        };
}

/// The menu a [GitLamaContextMenuWidget] would show at the origin, in the
/// test view, so a test can inspect and choose its items without an
/// operating-system menu.
extension ContextMenuModel on GitLamaContextMenuWidget {
  FutureOr<Menu?> testMenu([Offset position = Offset.zero]) {
    Menu? convert(List<NativeMenuAction>? items) =>
        items == null ? null : nativeMenuFromActions(items);
    final items = menuItems(position);
    return items is Future<List<NativeMenuAction>?>
        ? items.then(convert)
        : convert(items);
  }
}
