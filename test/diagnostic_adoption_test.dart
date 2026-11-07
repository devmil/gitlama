import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:devmil_logging/devmil_logging.dart';
import 'package:gitlama/logging/logging_utils.dart';

void main() {
  test(
    'production sink retains safe history without private payloads or console output',
    () async {
      final history = DiagnosticHistory.instance;
      history.clear();
      history.disableDetailed();
      final previous = debugPrint;
      final console = <String>[];
      debugPrint = (message, {wrapWidth}) {
        if (message != null) console.add(message);
      };
      await LoggingUtils.initialize();
      try {
        Logger('Adoption').info(
          const DiagnosticEvent('operation_started', fields: {'stage': 2}),
        );
        Logger('Adoption').warning(
          'private-content-sentinel',
          StateError('credential-sentinel'),
        );
        history.enableDetailed();
        Logger(
          'Adoption',
        ).fine(const DiagnosticEvent('operation_detail', detailed: true));
        final snapshot = history.snapshot(
          application: 'gitlama',
          version: 'test',
        );
        expect(snapshot, contains('operation_started stage=2'));
        expect(snapshot, contains('operation_detail'));
        expect(snapshot, isNot(contains('sentinel')));
        expect(console, isEmpty);
        history.disableDetailed();
        Logger(
          'Adoption',
        ).info(const DiagnosticEvent('detail_disabled', detailed: true));
        expect(
          history.snapshot(application: 'gitlama', version: 'test'),
          isNot(contains('detail_disabled')),
        );
        history.clear();
        expect(history.count, 0);
      } finally {
        await LoggingUtils.dispose();
        debugPrint = previous;
      }
    },
  );
}
