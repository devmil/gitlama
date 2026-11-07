import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/models/repository_appearance.dart';
import 'package:gitlama/models/settings.dart';
import 'package:gitlama/models/workspace.dart';
import 'package:gitlama/widgets/gitlama_repo_tabs.dart';
import 'package:gitlama/widgets/repository_icon.dart';

import 'motion/motion_support.dart';

void main() {
  final closed = <int>[];
  final menus = <(int, Offset)>[];

  setUp(() {
    closed.clear();
    menus.clear();
  });

  Widget tabs({bool withIcon = false}) => motionHost(
    SizedBox(
      width: 900,
      child: GitLamaRepoTabs(
        workspace: const WorkspaceState(
          tabs: [
            RepositoryTabState(
              id: 1,
              generation: 1,
              label: 'alpha',
              phase: RepositoryTabPhase.open,
            ),
            RepositoryTabState(
              id: 2,
              generation: 1,
              label: 'beta',
              phase: RepositoryTabPhase.open,
            ),
          ],
          activeTabId: 1,
        ),
        onActivate: (_) {},
        onClose: closed.add,
        onMoveTab: (_, _, _) {},
        onOpenRepository: () {},
        leadingBuilder: withIcon
            ? (context, tab) => tab.id == 2
                  ? RepositoryIcon(
                      appearance: RepositoryAppearance(
                        identity: NativePathIdentity(
                          platform: NativePathPlatform.unix,
                          units: '/beta'.codeUnits,
                        ),
                        icon: 'box',
                        color: 'teal',
                      ),
                    )
                  : null
            : null,
        onContextMenu: (id, position) => menus.add((id, position)),
      ),
    ),
  );

  testWidgets('close control stays at the right edge of the tab', (
    tester,
  ) async {
    await tester.pumpWidget(tabs());
    final target = find.byKey(const ValueKey(('tab-pill', 1)));
    final close = find.byTooltip('Close alpha');
    expect(close, findsOneWidget);
    expect(
      tester.getRect(target).right - tester.getRect(close).right,
      MeridianSpace.space3,
    );
  });

  testWidgets('a middle click closes the tab under the pointer', (
    tester,
  ) async {
    await tester.pumpWidget(tabs());
    await tester.tap(find.text('beta'), buttons: kMiddleMouseButton);
    await tester.pump();
    expect(closed, [2]);
  });

  testWidgets('a right click and the menu key ask for the tab menu', (
    tester,
  ) async {
    await tester.pumpWidget(tabs());
    await tester.tap(find.text('alpha'), buttons: kSecondaryMouseButton);
    await tester.pump();
    expect(menus.single.$1, 1);
    expect(closed, isEmpty);

    Focus.of(tester.element(find.text('beta'))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
    await tester.pump();
    expect(menus.map((menu) => menu.$1), [1, 2]);
  });

  testWidgets('a hairline separates resting tabs but not the active pill', (
    tester,
  ) async {
    Widget strip(int active) => motionHost(
      SizedBox(
        width: 900,
        child: GitLamaRepoTabs(
          workspace: WorkspaceState(
            tabs: [
              for (final (id, label) in [
                (1, 'alpha'),
                (2, 'beta'),
                (3, 'gamma'),
              ])
                RepositoryTabState(
                  id: id,
                  generation: 1,
                  label: label,
                  phase: RepositoryTabPhase.open,
                ),
            ],
            activeTabId: active,
          ),
          onActivate: (_) {},
          onClose: closed.add,
          onMoveTab: (_, _, _) {},
          onOpenRepository: () {},
        ),
      ),
    );
    double opacity(int id) => tester
        .widget<AnimatedOpacity>(
          find.descendant(
            of: find.byKey(ValueKey(('tab-separator', id))),
            matching: find.byType(AnimatedOpacity),
          ),
        )
        .opacity;

    await tester.pumpWidget(strip(1));
    expect(opacity(1), 0);
    expect(opacity(2), 1);
    // The last tab has nothing to be separated from.
    expect(find.byKey(const ValueKey(('tab-separator', 3))), findsNothing);
    final separator = tester.getRect(
      find.byKey(const ValueKey(('tab-separator', 2))),
    );
    expect(
      separator.left,
      greaterThanOrEqualTo(tester.getRect(find.text('beta')).right),
    );
    expect(
      separator.right,
      lessThanOrEqualTo(tester.getRect(find.text('gamma')).left),
    );

    await tester.pumpWidget(strip(3));
    expect(opacity(1), 1);
    expect(opacity(2), 0);
  });

  testWidgets('a repository icon leads its tab label', (tester) async {
    await tester.pumpWidget(tabs(withIcon: true));
    final icon = find.byKey(const ValueKey('repository-icon'));
    expect(icon, findsOneWidget);
    expect(
      tester.widget<MeridianIcon>(
        find.descendant(of: icon, matching: find.byType(MeridianIcon)),
      ),
      isA<MeridianIcon>()
          .having((icon) => icon.name, 'name', 'box')
          .having(
            (icon) => icon.color,
            'color',
            MeridianTheme.of(tester.element(icon)).colors.series[1],
          ),
    );
    expect(
      tester.getRect(icon).right,
      lessThan(tester.getRect(find.text('beta')).left),
    );
  });

  testWidgets('a dragged tab lifts only its pill, with its own fill', (
    tester,
  ) async {
    await tester.pumpWidget(tabs());
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('beta')),
    );
    await gesture.moveBy(const Offset(-40, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final lift = find.byType(MeridianLift);
    expect(lift, findsOneWidget);
    // The lifted surface is the 26 px pill, not the taller tab slot.
    expect(tester.getSize(lift).height, MeridianLayout.tabPillHeight);
    final fill = tester
        .widgetList<AnimatedContainer>(
          find.descendant(of: lift, matching: find.byType(AnimatedContainer)),
        )
        .first;
    expect(
      (fill.decoration! as BoxDecoration).color,
      MeridianTheme.of(tester.element(lift)).colors.pane,
    );
    await gesture.up();
    await tester.pumpAndSettle();
  });

  group('tab groups', () {
    final toggled = <int>[];
    final renamedTabs = <(int, String)>[];
    final renamedGroups = <(int, String)>[];
    final activated = <int>[];
    final movedTabs = <(int, int, int?)>[];
    final movedGroups = <(int, int)>[];
    setUp(() {
      toggled.clear();
      renamedTabs.clear();
      renamedGroups.clear();
      activated.clear();
      movedTabs.clear();
      movedGroups.clear();
    });

    RepositoryTabState tab(int id, String label, {int? group}) =>
        RepositoryTabState(
          id: id,
          generation: 1,
          label: label,
          phase: RepositoryTabPhase.open,
          groupId: group,
        );

    Widget grouped({
      bool collapsed = false,
      String name = 'Client',
      String? icon,
      GlobalKey<GitLamaRepoTabsState>? key,
    }) => motionHost(
      SizedBox(
        width: 900,
        child: GitLamaRepoTabs(
          key: key,
          workspace: WorkspaceState(
            tabs: [
              tab(1, 'alpha'),
              tab(2, 'beta', group: 7),
              tab(3, 'gamma', group: 7),
            ],
            activeTabId: 1,
            groups: [
              RepositoryTabGroup(
                id: 7,
                name: name,
                color: const PaletteColor(RepositoryAppearanceColor.violet),
                icon: icon,
                collapsed: collapsed,
              ),
            ],
          ),
          onActivate: activated.add,
          onClose: closed.add,
          onMoveTab: (id, index, group) => movedTabs.add((id, index, group)),
          onMoveGroup: (id, index) => movedGroups.add((id, index)),
          onOpenRepository: () {},
          labelBuilder: (tab) => tab.id == 1 ? 'Website' : tab.label,
          onRenameTab: (id, name) => renamedTabs.add((id, name)),
          onToggleGroup: toggled.add,
          onGroupContextMenu: (id, position) => menus.add((id, position)),
          onRenameGroup: (id, name) => renamedGroups.add((id, name)),
        ),
      ),
    );

    Finder chip() => find.byKey(const ValueKey(('tab-group-chip', 7)));

    Rect pill(WidgetTester tester, int id) =>
        tester.getRect(find.byKey(ValueKey(('tab-pill', id))));

    /// Drags from [from] by [dx] in small steps, and drops.
    Future<void> drag(WidgetTester tester, Offset from, double dx) async {
      final gesture = await tester.startGesture(
        from,
        kind: PointerDeviceKind.mouse,
      );
      for (var step = 0; step < 8; step++) {
        await gesture.moveBy(Offset(dx / 8, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      await tester.pump(const Duration(milliseconds: 300));
      await gesture.up();
      await tester.pumpAndSettle();
    }

    // The strip reads Website, the Client chip, beta, gamma.
    testWidgets('a tab dragged past the chip joins the group', (tester) async {
      await tester.pumpWidget(grouped());
      await tester.pumpAndSettle();
      await drag(
        tester,
        pill(tester, 1).center,
        tester.getSize(chip()).width + MeridianSpace.space2 + 2,
      );
      expect(movedTabs, [(1, 0, 7)]);
    });

    testWidgets('a tab dragged before the chip leaves the group', (
      tester,
    ) async {
      await tester.pumpWidget(grouped());
      await tester.pumpAndSettle();
      await drag(
        tester,
        pill(tester, 2).center,
        -(tester.getSize(chip()).width + MeridianSpace.space2 + 2),
      );
      expect(movedTabs, [(2, 1, null)]);
    });

    testWidgets('a dragged chip carries its group', (tester) async {
      await tester.pumpWidget(grouped());
      await tester.pumpAndSettle();
      final start = tester.getRect(chip());
      await drag(tester, start.center, pill(tester, 1).left - start.left - 2);
      expect(movedGroups, [(7, 0)]);
      expect(movedTabs, isEmpty);
    });

    testWidgets('a group shows its icon before its name, or alone', (
      tester,
    ) async {
      await tester.pumpWidget(grouped(icon: 'server'));
      await tester.pumpAndSettle();
      final icon = find.byKey(const ValueKey('tab-group-icon'));
      expect(icon, findsOneWidget);
      expect(
        tester.getRect(icon).right,
        lessThan(tester.getRect(find.text('Client')).left),
      );

      await tester.pumpWidget(grouped(name: '', icon: 'server'));
      await tester.pumpAndSettle();
      expect(icon, findsOneWidget);
      expect(tester.getSize(chip()).width, MeridianLayout.tabGroupChipHeight);
    });

    testWidgets('a chip leads the group and a rule runs under it', (
      tester,
    ) async {
      await tester.pumpWidget(grouped());
      await tester.pumpAndSettle();
      expect(find.text('Website'), findsOneWidget);
      expect(find.text('alpha'), findsNothing);
      final chipRect = tester.getRect(chip());
      final beta = tester.getRect(find.text('beta'));
      expect(chipRect.right, lessThan(beta.left));
      expect(
        chipRect.left,
        greaterThan(tester.getRect(find.text('Website')).right),
      );
      // One rule runs under the chip and both tabs, across the gaps.
      final rule = tester.getRect(
        find.byKey(const ValueKey(('tab-group-rule', 7))),
      );
      expect(rule.left, chipRect.left);
      expect(rule.right, pill(tester, 3).right);
      expect(rule.height, MeridianLayout.tabRuleHeight);

      await tester.tap(chip());
      await tester.pump();
      expect(toggled, [7]);
      await tester.tap(chip(), buttons: kSecondaryMouseButton);
      await tester.pump();
      expect(menus.single.$1, 7);
    });

    testWidgets('a collapsed group folds its tabs into a counted chip', (
      tester,
    ) async {
      await tester.pumpWidget(grouped());
      await tester.pumpAndSettle();
      final open = tester.getRect(chip()).width;
      await tester.pumpWidget(grouped(collapsed: true));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsOneWidget);
      expect(tester.getRect(chip()).width, greaterThan(open));
      expect(find.text('beta').hitTestable(), findsNothing);
      expect(find.byKey(const ValueKey(('tab-group-rule', 7))), findsNothing);
      expect(
        tester.getSemantics(chip()),
        matchesSemantics(
          label: 'Client, tab group, 2 tabs',
          isButton: true,
          hasExpandedState: true,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('an unnamed group shows its colour as a dot', (tester) async {
      await tester.pumpWidget(grouped(name: ''));
      await tester.pumpAndSettle();
      final size = tester.getSize(chip());
      expect(size.width, MeridianLayout.tabGroupChipHeight);
      expect(find.byTooltip('Collapse Violet group'), findsOneWidget);
    });

    testWidgets('a second click on the active tab names it in place', (
      tester,
    ) async {
      await tester.pumpWidget(grouped());
      await tester.pumpAndSettle();
      await tester.tap(find.text('Website'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('Website'));
      await tester.pumpAndSettle();
      expect(activated, [1]);
      final field = find.byType(EditableText);
      expect(field, findsOneWidget);
      final editable = tester.widget<EditableText>(field);
      expect(editable.controller.selection.extentOffset, 'Website'.length);
      await tester.enterText(field, 'Docs');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(renamedTabs, [(1, 'Docs')]);
      expect(find.byType(EditableText), findsNothing);

      // A click on a resting tab only activates it.
      await tester.tap(find.text('beta'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(find.text('beta'));
      await tester.pumpAndSettle();
      expect(find.byType(EditableText), findsNothing);
    });

    testWidgets('Escape cancels naming a group in place', (tester) async {
      final key = GlobalKey<GitLamaRepoTabsState>();
      await tester.pumpWidget(grouped(key: key));
      await tester.pumpAndSettle();
      key.currentState!.renameGroup(7);
      await tester.pumpAndSettle();
      expect(
        tester.getSize(chip()).width,
        MeridianLayout.tabGroupChipEditWidth,
      );
      await tester.enterText(find.byType(EditableText), 'Other');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(renamedGroups, isEmpty);
      expect(find.text('Client'), findsOneWidget);

      key.currentState!.renameGroup(7);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(EditableText), 'Other');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(renamedGroups, [(7, 'Other')]);
    });
  });
}
