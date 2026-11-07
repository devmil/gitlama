import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:meridian_native_menus/meridian_native_menus.dart' as native;
import 'package:meridian_ui/meridian_ui.dart';

/// The single presentation boundary for desktop context and action menus.
///
/// GitLama builds menus as [NativeMenuItem] data and shows them through
/// Meridian's native menu companion (`meridian_native_menus`): `NSMenu` on
/// macOS and a Win32 popup menu from the package's host plugin, and the
/// `super_native_extensions` GTK menu on Linux. Unsupported platforms and
/// plugin failures never substitute a Flutter menu.
abstract final class NativeMenus {
  /// Installs the native presenter for every Meridian menu and text field
  /// below [child]. Put it at each app root, inside the `MaterialApp`
  /// builder.
  static Widget scope({required Widget child}) =>
      native.MeridianNativeMenus.scope(child: child);

  /// On Linux the plugin anchors a menu to the last button press, which only
  /// its drag context records; create it once per engine at start-up.
  static Future<void> prepare() => native.MeridianNativeMenus.prepare();

  /// Shows [entries] at [position] (global logical pixels). Completes with
  /// whether an item was chosen, after its action ran once the menu closed.
  static Future<bool> show(
    BuildContext context,
    List<MeridianMenuEntry> entries,
    Offset position,
  ) => native.MeridianNativeMenus.show(context, entries, position);
}

/// Shows a Meridian menu (a select, a split toolbar button, a menu anchor)
/// as the operating system's native menu below [anchor].
Future<void> presentNativeMeridianMenu(
  BuildContext context, {
  required Rect anchor,
  required List<MeridianMenuEntry> entries,
}) => native.MeridianNativeMenus.present(
  context,
  anchor: anchor,
  entries: entries,
);

/// Menu content is data, never a Flutter popup widget tree.
class NativeMenuItem<T> {
  const NativeMenuItem({
    required this.value,
    required this.title,
    this.enabled = true,
    this.disabledReason,
    this.checked,
    this.activator,
    this.icon,
    this.danger = false,
  }) : separator = false,
       header = false,
       children = null;

  /// Opens [children] beside the menu (a native submenu).
  const NativeMenuItem.submenu({
    required this.title,
    required List<NativeMenuItem<T>> this.children,
    this.icon,
    this.enabled = true,
    this.disabledReason,
  }) : value = null,
       activator = null,
       danger = false,
       checked = null,
       header = false,
       separator = false;

  const NativeMenuItem.separator()
    : value = null,
      title = '',
      activator = null,
      icon = null,
      danger = false,
      enabled = false,
      disabledReason = null,
      checked = null,
      header = false,
      separator = true,
      children = null;

  /// Names the group of items below it; it cannot be chosen.
  const NativeMenuItem.header(this.title)
    : value = null,
      activator = null,
      icon = null,
      danger = false,
      enabled = false,
      disabledReason = null,
      checked = null,
      header = true,
      separator = false,
      children = null;

  final T? value;
  final String title;

  /// Whether the item can be chosen; an item with a [disabledReason] never
  /// can.
  final bool enabled;

  /// Why the item is unavailable. Native menus show no tooltips, so the
  /// reason follows the title.
  final String? disabledReason;
  final bool? checked;
  final bool separator;
  final bool header;
  final SingleActivator? activator;

  /// Lucide name, or a name registered in the app's `MeridianIconSet`.
  final String? icon;
  final bool danger;

  /// The submenu's items; `null` for anything but a submenu.
  final List<NativeMenuItem<T>>? children;

  bool get available => enabled && disabledReason == null;

  /// The title as the menu shows it, with the reason when unavailable.
  String get shownTitle =>
      disabledReason == null ? title : '$title — $disabledReason';
}

/// The Meridian menu model of [items]. Choosing an available item calls
/// [onSelected] with its value once the menu has closed. An item whose
/// value is [initialValue] is checked unless it says otherwise. A submenu
/// that is unavailable is shown as an unavailable item.
List<MeridianMenuEntry> meridianEntriesFromItems<T>(
  List<NativeMenuItem<T>> items, {
  required ValueChanged<T> onSelected,
  T? initialValue,
}) => [
  for (final item in items)
    if (item.separator)
      const MeridianMenuDivider()
    else if (item.header)
      MeridianMenuHeader(item.title)
    else if (item.children case final children?)
      MeridianMenuItem(
        label: item.shownTitle,
        icon: item.icon,
        children: item.available && children.isNotEmpty
            ? meridianEntriesFromItems(
                children,
                onSelected: onSelected,
                initialValue: initialValue,
              )
            : null,
      )
    else
      MeridianMenuItem(
        label: item.shownTitle,
        icon: item.icon,
        danger: item.danger,
        shortcut: menuShortcutKeycaps(item.activator),
        checked:
            item.checked ??
            (initialValue != null && item.value == initialValue ? true : null),
        onSelected: switch (item.value) {
          final T value when item.available => () => onSelected(value),
          _ => null,
        },
      ),
];

/// The keycaps Meridian's menu model shows for [activator]; null for none
/// or for a key a native menu cannot name.
List<String>? menuShortcutKeycaps(SingleActivator? activator) {
  if (activator == null) return null;
  final key = _keyName(activator.trigger);
  if (key == null) return null;
  return [
    if (activator.control) 'Ctrl',
    if (activator.alt) 'Alt',
    if (activator.shift) 'Shift',
    if (activator.meta) 'Win',
    key,
  ];
}

String? _keyName(LogicalKeyboardKey key) {
  const named = {
    0x0010000000d: 'Enter',
    0x00100000009: 'Tab',
    0x00000000020: 'Space',
    0x00100000008: 'Backspace',
    0x0010000007f: 'Delete',
    0x0010000001b: 'Esc',
    0x00100000304: 'Up',
    0x00100000301: 'Down',
    0x00100000302: 'Left',
    0x00100000303: 'Right',
    0x00100000306: 'Home',
    0x00100000305: 'End',
    0x00100000308: 'PageUp',
    0x00100000307: 'PageDown',
  };
  final name = named[key.keyId];
  if (name != null) return name;
  final label = key.keyLabel;
  if (RegExp(r'^F([1-9]|1[0-9]|2[0-4])$').hasMatch(label)) return label;
  return label.runes.length == 1 ? label.toUpperCase() : null;
}

/// A menu item that runs its own action once the menu has closed. Context
/// menus use this model; feature code never builds plugin menu objects.
typedef NativeMenuAction = NativeMenuItem<VoidCallback>;

/// Items whose values are handled by [onSelected], as self-running actions.
List<NativeMenuAction> nativeMenuActions<T>(
  List<NativeMenuItem<T>> items,
  ValueChanged<T> onSelected,
) => [
  for (final item in items)
    if (item.separator)
      const NativeMenuAction.separator()
    else if (item.header)
      NativeMenuAction.header(item.title)
    else if (item.children case final children?)
      NativeMenuAction.submenu(
        title: item.title,
        icon: item.icon,
        enabled: item.enabled,
        disabledReason: item.disabledReason,
        children: nativeMenuActions(children, onSelected),
      )
    else
      NativeMenuAction(
        value: switch (item.value) {
          final T value => () => onSelected(value),
          null => null,
        },
        title: item.title,
        enabled: item.enabled,
        disabledReason: item.disabledReason,
        checked: item.checked,
        activator: item.activator,
        icon: item.icon,
        danger: item.danger,
      ),
];

/// The Meridian menu model of self-running [items].
List<MeridianMenuEntry> meridianEntriesFromActions(
  List<NativeMenuAction> items,
) => meridianEntriesFromItems<VoidCallback>(
  items,
  onSelected: (action) => action(),
);

/// [items] with destructive items moved to the end, behind a separator, in
/// their original order. Separators left at either end or doubled are
/// dropped.
List<NativeMenuItem<T>> withDestructiveLast<T>(List<NativeMenuItem<T>> items) {
  List<NativeMenuItem<T>> tidy(Iterable<NativeMenuItem<T>> items) {
    final result = <NativeMenuItem<T>>[];
    for (final item in items) {
      if (item.separator && (result.isEmpty || result.last.separator)) {
        continue;
      }
      result.add(item);
    }
    if (result.isNotEmpty && result.last.separator) result.removeLast();
    return result;
  }

  final safe = tidy(items.where((item) => !item.danger));
  final destructive = tidy(items.where((item) => item.danger));
  return [
    ...safe,
    if (safe.isNotEmpty && destructive.isNotEmpty)
      NativeMenuItem<T>.separator(),
    ...destructive,
  ];
}

/// Shows [items] at [position] and completes with the chosen value, once the
/// menu has closed; null when nothing was chosen or the context went away.
Future<T?> showNativeMenuItems<T>({
  required BuildContext context,
  required Offset position,
  required List<NativeMenuItem<T>> items,
  T? initialValue,
}) async {
  T? selected;
  await NativeMenus.show(
    context,
    meridianEntriesFromItems<T>(
      items,
      initialValue: initialValue,
      onSelected: (value) {
        if (context.mounted) selected = value;
      },
    ),
    position,
  );
  return selected;
}

class NativeMenuButton<T> extends StatefulWidget {
  const NativeMenuButton({
    required this.itemBuilder,
    required this.onSelected,
    super.key,
    this.tooltip,
    this.enabled = true,
    this.child,
    this.icon,
    this.padding = const EdgeInsets.all(MeridianSpace.space3),
    this.iconSize,
    this.constraints,
    this.initialValue,
    this.beforeOpen,
  });

  final List<NativeMenuItem<T>> Function(BuildContext) itemBuilder;

  /// Runs before [itemBuilder] each time the menu opens, for what can only
  /// be told then, such as whether a file exists.
  final Future<void> Function()? beforeOpen;
  final ValueChanged<T> onSelected;
  final String? tooltip;
  final bool enabled;
  final Widget? child;
  final Widget? icon;
  final EdgeInsetsGeometry padding;
  final double? iconSize;
  final BoxConstraints? constraints;
  final T? initialValue;

  @override
  State<NativeMenuButton<T>> createState() => _NativeMenuButtonState<T>();
}

class _NativeMenuButtonState<T> extends State<NativeMenuButton<T>> {
  final _focus = FocusNode();
  bool _showing = false;

  Future<void> _open() async {
    if (_showing || !widget.enabled) return;
    _showing = true;
    _focus.requestFocus();
    try {
      await widget.beforeOpen?.call();
      if (!mounted) return;
      final items = widget.itemBuilder(context);
      final box = context.findRenderObject()! as RenderBox;
      final value = await showNativeMenuItems<T>(
        context: context,
        position: box.localToGlobal(Offset(0, box.size.height)),
        items: items,
        initialValue: widget.initialValue,
      );
      if (!mounted) return;
      _focus.requestFocus();
      if (value != null && widget.enabled) widget.onSelected(value);
    } finally {
      _showing = false;
    }
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label =
        widget.tooltip ?? MaterialLocalizations.of(context).showMenuTooltip;
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.arrowDown): ActivateIntent(),
      },
      child: Tooltip(
        message: label,
        child: Semantics(
          excludeSemantics: true,
          button: true,
          enabled: widget.enabled,
          label: label,
          onTap: widget.enabled ? _open : null,
          child: MeridianInteraction(
            focusNode: _focus,
            onTap: widget.enabled ? _open : null,
            borderRadius: BorderRadius.circular(context.meridian.radius.md),
            builder: (context, state) => Container(
              constraints: widget.child == null
                  ? widget.constraints ??
                        const BoxConstraints.tightFor(
                          width: MeridianSize.control,
                          height: MeridianSize.control,
                        )
                  : null,
              padding: widget.child == null ? widget.padding : EdgeInsets.zero,
              decoration: BoxDecoration(
                color: state.fill(
                  rest: meridianClear(
                    MeridianSurfaceScope.hoverFillOf(context),
                  ),
                  hoverFill: MeridianSurfaceScope.hoverFillOf(context),
                  ink: context.meridian.colors.ink,
                ),
                borderRadius: BorderRadius.circular(context.meridian.radius.md),
              ),
              child:
                  widget.child ??
                  Center(
                    child: IconTheme(
                      data: IconThemeData(
                        size: widget.iconSize ?? MeridianSize.icon,
                      ),
                      child: widget.icon ?? const MeridianIcon('more'),
                    ),
                  ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Supplies the items of a context menu opened at [position] (global
/// coordinates); `null` or no items opens no menu.
typedef NativeMenuItemsProvider =
    FutureOr<List<NativeMenuAction>?> Function(Offset position);

/// Native right-click and keyboard (context-menu key, Shift+F10) context
/// menu, using the same menu model as action buttons. When the menu closes
/// without a choice, focus returns to where it was.
class GitLamaContextMenuWidget extends StatelessWidget {
  const GitLamaContextMenuWidget({
    required this.menuItems,
    required this.child,
    super.key,
  });
  final NativeMenuItemsProvider menuItems;
  final Widget child;

  @override
  Widget build(BuildContext context) => native.MeridianNativeContextMenuRegion(
    entries: (position) async => switch (await menuItems(position)) {
      final items? => meridianEntriesFromActions(items),
      null => null,
    },
    child: child,
  );
}

/// Keeps Flutter's editing capabilities and localized labels, but delegates
/// their presentation to the same OS menu used by other context menus.
Widget nativeTextContextMenuBuilder(
  BuildContext context,
  EditableTextState editable,
) => native.nativeTextContextMenuBuilder(context, editable);
