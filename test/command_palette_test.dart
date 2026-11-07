import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/app/workspace/command_palette.dart';
import 'package:gitlama/models/app_command.dart';
import 'motion/motion_support.dart';

void main() {
  testWidgets('the search field keeps clear of the esc key', (tester) async {
    await tester.pumpWidget(
      motionHost(
        Builder(
          builder: (context) => MeridianButton(
            label: 'Open palette',
            onPressed: () => showCommandPalette<Object>(
              context: context,
              builder: (_) => CommandPaletteDialog(
                onRun: () {},
                hasRepository: false,
                disabledSelectionCommands: {},
                shortcuts: {},
                activeScopes: {},
                customCommands: [],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open palette'));
    await tester.pumpAndSettle();
    final field = tester.getRect(
      find.ancestor(
        of: find.byKey(const Key('command-palette-query')),
        matching: find.byType(MeridianTextField),
      ),
    );
    final esc = tester.getRect(find.byType(MeridianKbd).first);
    // The focus halo grows a hairline past the field; the key stays clear.
    expect(esc.left - field.right, greaterThanOrEqualTo(MeridianSpace.space4));
  });

  testWidgets(
    'palette arrows select commands while search retains focus and Enter runs',
    (tester) async {
      Object? result;
      var runs = 0;
      await tester.pumpWidget(
        motionHost(
          Builder(
            builder: (context) => MeridianButton(
              label: 'Open palette',
              onPressed: () async {
                result = await showCommandPalette<Object>(
                  context: context,
                  builder: (_) => CommandPaletteDialog(
                    onRun: () => runs++,
                    hasRepository: false,
                    disabledSelectionCommands: {},
                    shortcuts: {},
                    activeScopes: {},
                    customCommands: [],
                  ),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open palette'));
      await tester.pumpAndSettle();
      final focus = FocusManager.instance.primaryFocus;
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      final list = tester.state<ScrollableState>(
        find
            .descendant(
              of: find.byType(CommandPaletteDialog),
              matching: find.byType(Scrollable),
            )
            .last,
      );
      expect(list.position.pixels, greaterThan(0));
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        find
            .byWidgetPredicate(
              (widget) => widget is MeridianListRow && widget.selected,
            )
            .hitTestable(),
        findsOneWidget,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      expect(
        tester
            .widgetList<MeridianListRow>(find.byType(MeridianListRow))
            .where((row) => row.selected)
            .single
            .title,
        // Open Remote Repository follows Open Repository; it is always
        // offered.
        'Open Remote Repository…',
      );
      expect(FocusManager.instance.primaryFocus, same(focus));
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(runs, 1);
      expect(result, AppCommandId.openRemoteRepository);
    },
  );
}
