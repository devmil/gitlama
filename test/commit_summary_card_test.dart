import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/inspector/commit_summary_card.dart';
import 'package:gitlama/models/inspection.dart';

import 'motion/motion_support.dart';

void main() {
  testWidgets('a long message scrolls inside its bounded card', (tester) async {
    tester.view.physicalSize = const Size(900, 500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final body = [for (var line = 1; line <= 80; line++) 'Line $line'];
    await tester.pumpWidget(
      motionHost(
        reduced: true,
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: CommitSummaryCard(
                detail: CommitIdentityDetail(
                  commit: '9090f078c055f4a697a0c3ac8240636d07e20de3',
                  tree: 'tree',
                  parents: const [],
                  author: 'Ada'.codeUnits,
                  authorTime: 1,
                  authorTimezone: const [],
                  committer: 'Ada'.codeUnits,
                  committerTime: 1,
                  committerTimezone: const [],
                  message: 'Subject\n\n${body.join('\n')}'.codeUnits,
                ),
                onSelectParent: (_) {},
              ),
            ),
            const Expanded(child: SizedBox(key: ValueKey('files-and-diff'))),
          ],
        ),
      ),
    );
    await tester.tap(find.text('Subject'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // The files and diff keep the rest of the pane however long the message.
    expect(
      tester.getSize(find.byKey(const ValueKey('files-and-diff'))).height,
      greaterThanOrEqualTo(300),
    );
    final scroll = find.byKey(const ValueKey('commit-summary-scroll'));
    expect(tester.getSize(scroll).height, lessThanOrEqualTo(200));

    // The end of the message, with the full hash, is reachable.
    await tester.dragUntilVisible(
      find.text('9090f078c055f4a697a0c3ac8240636d07e20de3'),
      scroll,
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .getRect(find.text('9090f078c055f4a697a0c3ac8240636d07e20de3'))
          .bottom,
      lessThanOrEqualTo(200),
    );
  });
}
