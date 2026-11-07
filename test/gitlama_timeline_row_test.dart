import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/app_theme.dart';
import 'package:gitlama/widgets/gitlama_timeline_row.dart';
import 'motion/motion_support.dart';

void main() {
  testWidgets('the rail paints above the selected row fill', (tester) async {
    await tester.pumpWidget(
      motionHost(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (index, selected) in const [(0, true), (1, false)])
              GitLamaTimelineRow(
                key: ValueKey('row-$index'),
                state: GitLamaTimelineState.succeeded,
                verb: 'Refresh',
                target: 'repo',
                metadata: '',
                time: 'now',
                first: index == 0,
                last: index == 1,
                selected: selected,
                onActivate: () {},
                expanded: selected ? const Text('output') : null,
              ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final colors = tester.element(find.byKey(const ValueKey('row-0'))).colors;
    final fill = find.byWidgetPredicate(
      (widget) => widget is ColoredBox && widget.color == colors.accentSoft,
    );
    expect(fill, findsOneWidget);
    // The rail is the fill's descendant, so the fill cannot cover it.
    expect(
      find.descendant(of: fill, matching: find.byType(PositionedDirectional)),
      findsOneWidget,
    );
    final rail = tester.getRect(
      find.descendant(of: fill, matching: find.byType(PositionedDirectional)),
    );
    final row = tester.getRect(find.byKey(const ValueKey('row-0')));
    // A first row's rail runs from its mark to the row's bottom edge.
    expect(rail.bottom, row.bottom);
  });
}
