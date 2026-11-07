import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_ui/meridian_ui.dart';
import 'package:gitlama/widgets/gitlama_composer.dart';

import 'motion/motion_support.dart';

void main() {
  const subjectHeight = 30.0;
  const footerHeight = 28.0;
  const minimum = 48.0;
  final description = find.byKey(const ValueKey('description'));

  Widget composer({required double height, required bool fill}) => motionHost(
    Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: 360,
        height: height,
        child: GitLamaComposer(
          fill: fill,
          descriptionMinHeight: minimum,
          subject: const SizedBox(height: subjectHeight),
          description: MeridianTextField(
            key: const ValueKey('description'),
            expands: fill,
            maxLines: fill ? null : 3,
            minLines: fill ? null : 2,
          ),
          footer: const SizedBox(height: footerHeight),
        ),
      ),
    ),
  );

  // Padding (space-5) on both sides, gaps (space-4) around the description.
  const chrome = 2 * MeridianSpace.space5 + 2 * MeridianSpace.space4;

  testWidgets('a composer with a height gives it to the description', (
    tester,
  ) async {
    await tester.pumpWidget(composer(height: 320, fill: true));
    expect(
      tester.getSize(description).height,
      320 - chrome - subjectHeight - footerHeight,
    );

    await tester.pumpWidget(composer(height: 420, fill: true));
    await tester.pumpAndSettle();
    expect(
      tester.getSize(description).height,
      420 - chrome - subjectHeight - footerHeight,
    );
  });

  testWidgets('below its minimum the description keeps it and scrolls', (
    tester,
  ) async {
    await tester.pumpWidget(composer(height: 120, fill: true));
    expect(tester.getSize(description).height, minimum);
    expect(tester.takeException(), isNull);
    final scroll = tester.state<ScrollableState>(
      find
          .descendant(
            of: find.byType(SingleChildScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(scroll.position.maxScrollExtent, greaterThan(0));
  });

  testWidgets('without a height the description keeps its lines', (
    tester,
  ) async {
    await tester.pumpWidget(composer(height: 420, fill: false));
    expect(
      tester.getSize(description).height,
      lessThan(420 - chrome - subjectHeight - footerHeight),
    );
  });
}
