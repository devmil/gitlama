import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/app/workspace/commit_archive_dialog.dart';
import 'package:gitlama/models/commit_archive.dart';
import 'package:meridian_ui/meridian_ui.dart';

import 'motion/motion_support.dart';

void main() {
  test('snapshot names join the repository and the short commit', () {
    const commit = '1a2b3c4d5e6f7a8b9c0d1a2b3c4d5e6f7a8b9c0d';
    expect(commitArchiveName('gitlama', commit), 'gitlama-1a2b3c4');
    expect(commitArchiveName('My Repo', commit), 'My-Repo-1a2b3c4');
    expect(commitArchiveName('a/b:c*', commit), 'a-b-c-1a2b3c4');
    expect(commitArchiveName('..', commit), 'snapshot-1a2b3c4');
  });

  testWidgets('the progress dialog counts files and cancels the save', (
    tester,
  ) async {
    void Function(CommitArchiveStatus)? report;
    bool Function()? canceled;
    final finished = Completer<CommitArchiveStatus>();
    Object? popped = 'open';
    await tester.pumpWidget(
      motionHost(
        Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () async {
                popped = await showMeridianDialog<Object>(
                  context: context,
                  builder: (context) => CommitArchiveProgressDialog(
                    save: (onProgress, isCanceled) {
                      report = onProgress;
                      canceled = isCanceled;
                      return finished.future;
                    },
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    expect(find.text('Reading the commit…'), findsOneWidget);

    report!(
      const CommitArchiveStatus(
        state: CommitArchiveState.running,
        files: 3,
        totalFiles: 10,
      ),
    );
    await tester.pump();
    expect(find.text('3 of 10 files'), findsOneWidget);
    expect(canceled!(), isFalse);

    await tester.tap(find.byKey(const ValueKey('commit-archive-cancel')));
    await tester.pump();
    expect(canceled!(), isTrue);
    finished.completeError(
      const CommitArchiveException(CommitArchiveFailureCode.canceled),
    );
    await tester.pumpAndSettle();
    expect(find.text('Saving snapshot'), findsNothing);
    expect(popped, isNotNull);
  });
}
