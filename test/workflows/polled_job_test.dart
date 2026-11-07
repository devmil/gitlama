import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/services/workflows/polled_job.dart';

void main() {
  PolledJob<int> job({
    required List<int> results,
    required List<BigInt> cancelled,
    Completer<BigInt>? started,
  }) => PolledJob<int>(
    start: () => started?.future ?? Future.value(BigInt.from(7)),
    poll: (token) async => results.removeAt(0),
    pending: (result) => result < 0,
    cancel: (token) async => cancelled.add(token),
    interval: Duration.zero,
  );

  test('a job polls while pending and completes with its result', () async {
    final cancelled = <BigInt>[];
    final polled = job(results: [-1, -1, 3], cancelled: cancelled);
    expect(await polled.run(), 3);
    expect(polled.running, isFalse);
    expect(cancelled, isEmpty);
  });

  test('stopping cancels a started job and drops its result', () async {
    final cancelled = <BigInt>[];
    final polled = job(
      results: List.filled(1000, -1, growable: true),
      cancelled: cancelled,
    );
    final result = polled.run();
    await pumpEventQueue();
    expect(polled.running, isTrue);
    await polled.stop();
    expect(await result, isNull);
    expect(cancelled, [BigInt.from(7)]);
  });

  test('a job stopped before it started is cancelled once it starts', () async {
    final cancelled = <BigInt>[];
    final started = Completer<BigInt>();
    final polled = job(results: [], cancelled: cancelled, started: started);
    final result = polled.run();
    await polled.stop();
    started.complete(BigInt.from(9));
    expect(await result, isNull);
    expect(cancelled, [BigInt.from(9)]);
  });
}
