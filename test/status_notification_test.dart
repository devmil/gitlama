import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/l10n/app_localizations.dart';
import 'package:gitlama/models/activity.dart';
import 'package:gitlama/models/operation_failure.dart';
import 'package:gitlama/models/repository_state.dart';
import 'package:gitlama/models/transfer.dart';
import 'package:gitlama/services/operation_center_service.dart';
import 'package:gitlama/widgets/status_notification.dart';
import 'package:meridian_ui/meridian_ui.dart';

void main() {
  testWidgets('status feedback replaces messages without moving content', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        builder: (context, child) => StatusNotificationScope(child: child!),
        home: Builder(
          builder: (context) => Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: Center(
                    child: TextButton(
                      onPressed: () => StatusNotificationScope.show(
                        context,
                        'Index updated',
                      ),
                      child: const Text('Update'),
                    ),
                  ),
                ),
                const SizedBox(
                  height: 24,
                  width: double.infinity,
                  child: StatusNotificationText(fallback: 'Ready'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final before = tester.getRect(find.text('Update'));
    final statusBefore = tester.getRect(find.byType(StatusNotificationText));
    await tester.tap(find.text('Update'));
    await tester.pump();
    expect(find.text('Index updated'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.getRect(find.text('Update')), before);
    expect(tester.getRect(find.byType(StatusNotificationText)), statusBefore);

    await tester.pump(const Duration(seconds: 5));
    final context = tester.element(find.text('Update'));
    StatusNotificationScope.show(context, 'Another operation completed');
    await tester.pump();
    expect(find.text('Another operation completed'), findsOneWidget);
    await tester.pump(MeridianDurations.select);
    expect(find.text('Index updated'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Another operation completed'), findsOneWidget);
    StatusNotificationScope.show(context, 'Operation failed', error: true);
    await tester.pump();
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: find.byType(StatusNotificationText),
              matching: find.text('Operation failed'),
            ),
          )
          .style
          ?.color,
      MeridianTheme.of(context).colors.danger,
    );
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Operation failed'), findsNWidgets(2));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Operation failed'), findsOneWidget);
    expect(tester.getRect(find.text('Update')), before);

    StatusNotificationScope.show(context, 'Closing');
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 8));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'a failure opens one dialog, reaches Logbook and copies only safe facts',
    (tester) async {
      final operations = OperationCenterService.empty();
      addTearDown(operations.dispose);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final session = RepositorySessionIdentity(
        nativeId: BigInt.one,
        generation: 1,
      );
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => StatusNotificationScope(
            operations: operations,
            loadActivity: (identity, id) async => ActivityPage(
              records: [
                ActivityRecord(
                  id: id,
                  executable: 'git',
                  arguments: const ['fetch', 'origin'],
                  startedAtUnixMs: BigInt.zero,
                  status: ActivityStatus.failed,
                  exitCode: 1,
                  stdout: Uint8List(0),
                  stdoutTotalBytes: BigInt.zero,
                  stdoutTruncated: false,
                  stderr: Uint8List.fromList(
                    utf8.encode("fatal: Unable to create 'x.lock'"),
                  ),
                  stderrTotalBytes: BigInt.from(32),
                  stderrTruncated: false,
                ),
              ],
              evictedThroughId: BigInt.zero,
            ),
            child: child!,
          ),
          home: const Scaffold(
            body: Column(
              children: [
                Expanded(child: Center(child: Text('Ready'))),
                SizedBox(height: 24, child: StatusNotificationText()),
              ],
            ),
          ),
        ),
      );
      final context = tester.element(find.text('Ready'));
      StatusNotificationScope.show(
        context,
        'private-path-and-secret-sentinel',
        error: true,
        details: const OperationFailureDetails(
          operation: UserOperationKind.unstage,
        ),
      );
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 20));
      final dialog = find.byKey(const ValueKey('operation-failure-dialog'));
      expect(dialog, findsOneWidget);
      expect(find.byType(MeridianBanner), findsNothing);
      expect(operations.current.failedCount, 1);
      // Without a Git command there is no output to offer.
      expect(
        find.byKey(const ValueKey('operation-failure-include-output')),
        findsNothing,
      );
      await tester.tap(find.text('Copy support report'));
      await tester.pumpAndSettle();
      expect(copied, contains('Operation: unstage'));
      expect(copied, isNot(contains('private-path-and-secret-sentinel')));

      // A second failure replaces the open dialog's content.
      StatusNotificationScope.show(
        context,
        'Fetch failed',
        error: true,
        details: OperationFailureDetails(
          operation: UserOperationKind.transfer,
          transfer: TransferFailureCode.rejected,
          activity: (session: session, id: BigInt.from(9)),
        ),
      );
      await tester.pumpAndSettle();
      expect(dialog, findsOneWidget);
      expect(
        find.descendant(of: dialog, matching: find.text('Fetch failed')),
        findsOneWidget,
      );
      expect(operations.current.failedCount, 2);
      await tester.tap(find.text('Git output'));
      await tester.pumpAndSettle();
      expect(find.textContaining('git fetch origin'), findsOneWidget);
      await tester.tap(find.text('Copy support report'));
      await tester.pumpAndSettle();
      expect(copied, contains('Code: transfer.rejected'));
      expect(copied, contains('Activity: 9'));
      expect(copied, isNot(contains('x.lock')));
      await tester.tap(
        find.byKey(const ValueKey('operation-failure-include-output')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy support report'));
      await tester.pumpAndSettle();
      expect(copied, contains("fatal: Unable to create 'x.lock'"));
      expect(
        find.text(
          'Support report copied with Git output. Check it before you send it.',
        ),
        findsOneWidget,
      );

      StatusNotificationScope.show(context, 'Another operation succeeded');
      await tester.pumpAndSettle();
      expect(dialog, findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('operation-failure-close')));
      await tester.pumpAndSettle();
      expect(dialog, findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
