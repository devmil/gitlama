import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/widgets/native_menu.dart';
import 'package:meridian_native_menus/meridian_native_menus.dart'
    show MeridianNativeMenus, nativeMenuFromMeridian;
import 'package:meridian_ui/meridian_ui.dart';

import 'support/native_menu_model.dart';

/// Runs [body] with the real platform boundary: the companion package's
/// host channel on [platform], no test presenter.
void nativeTest(
  String name,
  Future<void> Function(WidgetTester) body, {
  TargetPlatform platform = TargetPlatform.windows,
}) {
  testWidgets(name, (tester) async {
    final presenter = nativeMenuTestPresenter;
    nativeMenuTestPresenter = null;
    MeridianNativeMenus.debugSupportedOverride = null;
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      MeridianNativeMenus.debugSupportedOverride = true;
      nativeMenuTestPresenter = presenter;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MeridianNativeMenus.channel, null);
    }
  });
}

void _host(Future<Object?> Function(MethodCall call) handler) =>
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(MeridianNativeMenus.channel, handler);

List<Map<Object?, Object?>> _items(MethodCall call) =>
    ((call.arguments as Map<Object?, Object?>)['items'] as List)
        .cast<Map<Object?, Object?>>();

Object? _idOf(MethodCall call, String title) =>
    _items(call).firstWhere((item) => item['title'] == title)['id'];

void main() {
  Future<BuildContext> host(WidgetTester tester, [Widget? child]) async {
    late BuildContext result;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              result = context;
              return child ?? const SizedBox();
            },
          ),
        ),
      ),
    );
    return result;
  }

  nativeTest('Win32 receives nested titles, states, separators and position', (
    tester,
  ) async {
    final context = await host(tester);
    MethodCall? request;
    _host((call) async {
      request = call;
      return _idOf(call, 'Branch & tag');
    });
    final selected = await showNativeMenuItems<String>(
      context: context,
      position: const Offset(120, 32),
      items: const [
        NativeMenuItem(
          value: 'branch',
          title: 'Branch & tag',
          checked: true,
          activator: SingleActivator(LogicalKeyboardKey.keyB, control: true),
        ),
        NativeMenuItem.separator(),
        NativeMenuItem.submenu(
          title: 'More',
          children: [
            NativeMenuItem(
              value: 'delete',
              title: 'Delete',
              disabledReason: 'Busy',
            ),
          ],
        ),
      ],
    );
    expect(selected, 'branch');
    final arguments = request!.arguments as Map<Object?, Object?>;
    expect(arguments['x'], 120.0);
    expect(arguments['y'], 32.0);
    final items = _items(request!);
    expect(items[0], containsPair('title', 'Branch & tag'));
    expect(items[0], containsPair('checked', true));
    expect(items[0], containsPair('shortcut', 'Ctrl+B'));
    expect(items[1], {'separator': true});
    expect((items[2]['items']! as List).single, {
      'id': isA<int>(),
      'title': 'Delete — Busy',
      'enabled': false,
      'checked': false,
    });
    expect(find.byType(PopupMenuItem<Object>), findsNothing);
  });

  nativeTest('macOS right-click uses the host menu', (tester) async {
    var selected = false;
    MethodCall? request;
    _host((call) async {
      request = call;
      return _idOf(call, 'Delete tag');
    });
    await host(
      tester,
      GitLamaContextMenuWidget(
        menuItems: (_) => [
          NativeMenuAction(value: () => selected = true, title: 'Delete tag'),
        ],
        child: const Text('tag'),
      ),
    );
    await tester.tap(find.text('tag'), buttons: kSecondaryMouseButton);
    await tester.pumpAndSettle();
    expect(_items(request!), [containsPair('title', 'Delete tag')]);
    expect(selected, isTrue);
  }, platform: TargetPlatform.macOS);

  nativeTest('cancel, unknown and disabled IDs never dispatch', (tester) async {
    final context = await host(tester);
    final items = [
      NativeMenuAction(
        value: () => fail('disabled action dispatched'),
        title: 'Unavailable',
        disabledReason: 'Busy',
      ),
    ];
    for (final answer in <Object? Function(MethodCall)>[
      (_) => null,
      (_) => -1,
      (call) => _items(call).single['id'],
    ]) {
      _host((call) async => answer(call));
      expect(
        await NativeMenus.show(
          context,
          meridianEntriesFromActions(items),
          Offset.zero,
        ),
        isFalse,
      );
    }
  });

  nativeTest('a late selection after the invoker went away is ignored', (
    tester,
  ) async {
    final context = await host(tester);
    final answer = Completer<Object?>();
    MethodCall? request;
    _host((call) {
      request = call;
      return answer.future;
    });
    final pending = NativeMenus.show(
      context,
      meridianEntriesFromActions([
        NativeMenuAction(value: () => fail('stale action'), title: 'Action'),
      ]),
      Offset.zero,
    );
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    answer.complete(_items(request!).single['id']);
    expect(await pending, isFalse);
  });

  test('Linux preparation never fails without the plugin', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await NativeMenus.prepare();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  nativeTest(
    'button opens native menu with keyboard and restores focus on cancel',
    (tester) async {
      final results = <Completer<Object?>>[];
      _host((_) {
        final result = Completer<Object?>();
        results.add(result);
        return result.future;
      });
      await host(
        tester,
        NativeMenuButton<String>(
          tooltip: 'Actions',
          onSelected: (_) => fail('cancel dispatched'),
          itemBuilder: (_) => [
            const NativeMenuItem(value: 'one', title: 'One'),
          ],
        ),
      );
      await tester.tap(find.byTooltip('Actions'));
      await tester.pump();
      final invokingFocus = FocusManager.instance.primaryFocus;
      expect(results, hasLength(1));
      await tester.tap(find.byTooltip('Actions'));
      await tester.pump();
      expect(results, hasLength(1));
      results[0].complete(null);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus, invokingFocus);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(results, hasLength(2));
      results[1].complete(null);
      await tester.pump();
    },
  );

  nativeTest('menu button can open, close, and reopen a dialog', (
    tester,
  ) async {
    _host((call) async => _items(call).single['id']);
    await host(
      tester,
      Builder(
        builder: (context) => NativeMenuButton<String>(
          tooltip: 'Actions',
          itemBuilder: (_) => [
            const NativeMenuItem(value: 'open', title: 'Open dialog'),
          ],
          onSelected: (_) => unawaited(
            showMeridianDialog<void>(
              context: context,
              builder: (dialogContext) => MeridianDialog(
                title: 'Menu dialog',
                actions: [
                  MeridianButton(
                    label: 'Close',
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.byTooltip('Actions'));
      await tester.pumpAndSettle();
      expect(find.text('Menu dialog'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Menu dialog'), findsNothing);
    }
  }, platform: TargetPlatform.macOS);

  nativeTest('context menu can open, close, and reopen a dialog', (
    tester,
  ) async {
    _host((call) async => _items(call).single['id']);
    await host(
      tester,
      Builder(
        builder: (context) => GitLamaContextMenuWidget(
          menuItems: (_) => [
            NativeMenuAction(
              title: 'Open dialog',
              value: () => unawaited(
                showMeridianDialog<void>(
                  context: context,
                  builder: (dialogContext) => MeridianDialog(
                    title: 'Context dialog',
                    actions: [
                      MeridianButton(
                        label: 'Close',
                        onPressed: () => Navigator.pop(dialogContext),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
          child: const Text('Row'),
        ),
      ),
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.tap(find.text('Row'), buttons: kSecondaryMouseButton);
      await tester.pumpAndSettle();
      expect(find.text('Context dialog'), findsOneWidget);
      await tester.tap(find.text('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Context dialog'), findsNothing);
    }
  }, platform: TargetPlatform.macOS);

  nativeTest('right-click and Shift+F10 use the same native context menu', (
    tester,
  ) async {
    var calls = 0;
    _host((_) async {
      calls++;
      return null;
    });
    final focus = FocusNode();
    addTearDown(focus.dispose);
    await host(
      tester,
      GitLamaContextMenuWidget(
        menuItems: (_) => [NativeMenuAction(value: () {}, title: 'Copy')],
        child: Focus(focusNode: focus, child: const Text('Row')),
      ),
    );
    await tester.tap(find.text('Row'), buttons: kSecondaryMouseButton);
    await tester.pump();
    expect(calls, 1);
    focus.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f10);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();
    expect(calls, 2);
    // Closed without a choice, the menu hands focus back.
    expect(FocusManager.instance.primaryFocus, focus);
  });

  nativeTest(
    'text editing menu sends native actions and preserves editing behavior',
    (tester) async {
      final controller = TextEditingController(text: 'hello world');
      addTearDown(controller.dispose);
      Object? chosen;
      _host((call) async => chosen = _idOf(call, 'Select all'));
      await host(
        tester,
        TextField(
          controller: controller,
          contextMenuBuilder: nativeTextContextMenuBuilder,
        ),
      );
      await tester.tap(find.byType(TextField));
      await tester.pump();
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText),
      );
      editable.showToolbar();
      await tester.pump();
      await tester.pump();
      expect(chosen, isNotNull);
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 11),
      );
      expect(find.byType(AdaptiveTextSelectionToolbar), findsNothing);
    },
  );

  test('an item with a reason is disabled and names it after the title', () {
    final selected = <String>[];
    final entries = meridianEntriesFromItems<String>(const [
      NativeMenuItem(value: 'a', title: 'Amend'),
      NativeMenuItem(
        value: 'b',
        title: 'Discard all',
        disabledReason: 'Not available here',
      ),
    ], onSelected: selected.add);
    final available = entries.first as MeridianMenuItem;
    final unavailable = entries.last as MeridianMenuItem;
    expect(available.label, 'Amend');
    expect(available.enabled, isTrue);
    expect(unavailable.label, 'Discard all — Not available here');
    expect(unavailable.enabled, isFalse);
    available.onSelected!();
    expect(selected, ['a']);
  });

  test('typed items become self-running actions with their state', () {
    final selected = <String>[];
    final actions = nativeMenuActions<String>(const [
      NativeMenuItem.header('Files'),
      NativeMenuItem(value: 'stage', title: 'Stage', icon: 'plus'),
      NativeMenuItem.separator(),
      NativeMenuItem.submenu(
        title: 'More',
        children: [NativeMenuItem(value: 'blame', title: 'Blame')],
      ),
      NativeMenuItem(
        value: 'discard',
        title: 'Discard',
        danger: true,
        disabledReason: 'Busy',
      ),
    ], selected.add);
    final menu = nativeMenuFromActions(actions);
    final header = menu.children.first as MenuAction;
    expect(header.header, isTrue);
    expect(header.attributes.disabled, isTrue);
    final stage = menu.children[1] as MenuAction;
    expect(stage.icon, 'plus');
    expect(menu.children[2], isA<MenuSeparator>());
    final discard = menu.children.last as MenuAction;
    expect(discard.attributes.destructive, isTrue);
    expect(discard.attributes.disabled, isTrue);
    expect(discard.title, 'Discard — Busy');
    stage.callback();
    ((menu.children[3] as Menu).children.single as MenuAction).callback();
    discard.callback();
    expect(selected, ['stage', 'blame']);
  });

  test('checks, shortcuts and unavailable submenus reach the menu model', () {
    final entries = meridianEntriesFromItems<int>(
      const [
        NativeMenuItem(value: 1, title: 'Tree'),
        NativeMenuItem(value: 2, title: 'List'),
        NativeMenuItem(value: 3, title: 'Flat', checked: false),
        NativeMenuItem(
          value: 4,
          title: 'Find',
          activator: SingleActivator(
            LogicalKeyboardKey.keyF,
            meta: true,
            shift: true,
          ),
        ),
        NativeMenuItem(
          value: 5,
          title: 'Next',
          activator: SingleActivator(LogicalKeyboardKey.arrowDown, alt: true),
        ),
        NativeMenuItem.submenu(
          title: 'Move to',
          disabledReason: 'Busy',
          children: [NativeMenuItem(value: 6, title: 'Inbox')],
        ),
      ],
      onSelected: (_) {},
      initialValue: 2,
    );
    final nodes = nativeMenuFromMeridian(entries);
    final menu = nativeMenuView(nodes, choose: (_) => () {});
    final states = [
      for (final element in menu.children.take(3))
        (element as MenuAction).state,
    ];
    expect(states, [
      MenuActionState.none,
      MenuActionState.checkOn,
      MenuActionState.checkOff,
    ]);
    expect((menu.children[3] as MenuAction).shortcut?.hostLabel, 'Shift+Win+F');
    expect((menu.children[4] as MenuAction).shortcut?.hostLabel, 'Alt+Down');
    final moveTo = menu.children[5] as MenuAction;
    expect(moveTo.title, 'Move to — Busy');
    expect(moveTo.attributes.disabled, isTrue);
  });

  test('destructive items move last behind one separator', () {
    final items = withDestructiveLast<String>(const [
      NativeMenuItem(value: 'delete', title: 'Delete', danger: true),
      NativeMenuItem.separator(),
      NativeMenuItem(value: 'open', title: 'Open'),
      NativeMenuItem.separator(),
      NativeMenuItem.separator(),
      NativeMenuItem(value: 'copy', title: 'Copy'),
      NativeMenuItem(value: 'reset', title: 'Reset', danger: true),
      NativeMenuItem.separator(),
    ]);
    expect(
      [for (final item in items) item.separator ? '-' : item.value],
      ['open', '-', 'copy', '-', 'delete', 'reset'],
    );
    expect(
      withDestructiveLast<String>(const [
        NativeMenuItem(value: 'delete', title: 'Delete', danger: true),
      ]).single.value,
      'delete',
    );
  });

  nativeTest(
    'the host receives icon masks and never dispatches a group title',
    (tester) async {
      final context = await host(tester);
      List<Map<Object?, Object?>>? items;
      _host((call) async {
        items = _items(call);
        return _idOf(call, 'Commit aaaaaaaaaa');
      });
      // Rasterizing an icon is real asynchronous engine work.
      final selected = await tester.runAsync(
        () => showNativeMenuItems<int>(
          context: context,
          position: Offset.zero,
          items: const [
            NativeMenuItem.header('Commit aaaaaaaaaa'),
            NativeMenuItem(value: 1, title: 'Create tag', icon: 'tag'),
            NativeMenuItem(value: 2, title: 'Unknown', icon: 'no-such-icon'),
          ],
        ),
      );
      expect(selected, isNull);
      expect(items![0], containsPair('header', true));
      expect(items![0], containsPair('enabled', false));
      final icon = items![1]['icon']! as Map<Object?, Object?>;
      final pixels = icon['rgba']! as Uint8List;
      expect(icon['width'], icon['height']);
      expect(
        pixels.length,
        (icon['width']! as int) * (icon['height']! as int) * 4,
      );
      // The mask has drawn pixels, not an empty picture.
      expect(pixels.any((value) => value != 0), isTrue);
      // A missing icon leaves the item without one instead of failing.
      expect(items![2], containsPair('title', 'Unknown'));
      expect(items![2].containsKey('icon'), isFalse);
    },
    platform: TargetPlatform.macOS,
  );

  testWidgets('menu button items carry icons, group titles and danger', (
    tester,
  ) async {
    Menu? shown;
    final previous = nativeMenuTestPresenter;
    nativeMenuTestPresenter = (context, menu, position) async {
      shown = menu;
      return const MenuResult(itemSelected: false);
    };
    addTearDown(() => nativeMenuTestPresenter = previous);
    final context = await host(tester);
    await showNativeMenuItems<int>(
      context: context,
      position: Offset.zero,
      items: const [
        NativeMenuItem.header('Branch'),
        NativeMenuItem(value: 1, title: 'Check out', icon: 'branch'),
        NativeMenuItem.separator(),
        NativeMenuItem(value: 2, title: 'Delete', icon: 'trash', danger: true),
      ],
    );
    final children = shown!.children;
    expect((children[0] as MenuAction).header, isTrue);
    expect((children[1] as MenuAction).icon, 'branch');
    expect(children[2], isA<MenuSeparator>());
    expect((children[3] as MenuAction).attributes.destructive, isTrue);
  });

  testWidgets('submenu items open beside the menu and report their value', (
    tester,
  ) async {
    Menu? shown;
    final previous = nativeMenuTestPresenter;
    nativeMenuTestPresenter = (context, menu, position) async {
      shown = menu;
      final submenu = menu.children.whereType<Menu>().single;
      submenu.children.whereType<MenuAction>().last.callback();
      return const MenuResult(itemSelected: true);
    };
    addTearDown(() => nativeMenuTestPresenter = previous);
    final context = await host(tester);
    final selected = await showNativeMenuItems<int>(
      context: context,
      position: Offset.zero,
      items: const [
        NativeMenuItem(value: 1, title: 'Rename'),
        NativeMenuItem.submenu(
          title: 'Color',
          icon: 'palette',
          children: [
            NativeMenuItem(value: 2, title: 'Blue', checked: false),
            NativeMenuItem(value: 3, title: 'Rose', checked: true),
          ],
        ),
      ],
    );
    final submenu = shown!.children[1] as Menu;
    expect(submenu.title, 'Color');
    expect(submenu.icon, 'palette');
    final rose = submenu.children.whereType<MenuAction>().last;
    expect(rose.state, MenuActionState.checkOn);
    expect(selected, 3);
  });
}
