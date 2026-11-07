import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gitlama/models/repository_drop.dart';
import 'package:gitlama/repositories/impl/native_repository_drop_repository.dart';

void main() {
  test(
    'native drop boundary accepts only 32 directories in source order',
    () async {
      final source = _FakeDropEventSource();
      final repository = NativeRepositoryDropRepository(
        source: source,
        pathType: (path) async => path.startsWith('directory-')
            ? FileSystemEntityType.directory
            : FileSystemEntityType.file,
      );
      await repository.initialize();
      final resultFuture = repository.events.firstWhere(
        (event) => event.phase == RepositoryDropPhase.dropped,
      );

      source.emit(
        DropDoneEvent(
          location: Offset.zero,
          files: [
            for (var index = 0; index < 34; index += 1)
              DropItemFile(index == 1 ? 'not-a-directory' : 'directory-$index'),
          ],
        ),
      );
      final result = await resultFuture;

      expect(result.directories, hasLength(31));
      expect(result.directories.first, 'directory-0');
      expect(result.directories.last, 'directory-31');
      expect(result.rejectedItems, 3);
      expect(source.initialized, isTrue);

      await repository.dispose();
      expect(source.listener, isNull);
    },
  );

  test(
    'native drop boundary publishes enter and exit without path data',
    () async {
      final source = _FakeDropEventSource();
      final repository = NativeRepositoryDropRepository(source: source);
      await repository.initialize();
      final eventsFuture = repository.events.take(2).toList();

      source.emit(DropEnterEvent(location: Offset.zero));
      source.emit(DropExitEvent(location: Offset.zero));
      final events = await eventsFuture;

      expect(events.map((event) => event.phase), [
        RepositoryDropPhase.entered,
        RepositoryDropPhase.exited,
      ]);
      expect(events.expand((event) => event.directories), isEmpty);

      await repository.dispose();
    },
  );

  test('classification failures do not poison later drop batches', () async {
    final source = _FakeDropEventSource();
    final repository = NativeRepositoryDropRepository(
      source: source,
      pathType: (path) async {
        if (path == 'unreadable') throw StateError('fixture failure');
        return FileSystemEntityType.directory;
      },
    );
    await repository.initialize();
    final resultsFuture = repository.events
        .where((event) => event.phase == RepositoryDropPhase.dropped)
        .take(2)
        .toList();

    source.emit(
      DropDoneEvent(location: Offset.zero, files: [DropItemFile('unreadable')]),
    );
    source.emit(
      DropDoneEvent(location: Offset.zero, files: [DropItemFile('repository')]),
    );
    final results = await resultsFuture;

    expect(results.first.directories, isEmpty);
    expect(results.first.rejectedItems, 1);
    expect(results.last.directories, const ['repository']);
    expect(results.last.rejectedItems, 0);

    await repository.dispose();
  });
}

final class _FakeDropEventSource implements RepositoryDropEventSource {
  RawDropListener? listener;
  var initialized = false;

  @override
  void initialize() => initialized = true;

  @override
  void addListener(RawDropListener value) => listener = value;

  @override
  void removeListener(RawDropListener value) {
    if (listener == value) listener = null;
  }

  void emit(DropEvent event) => listener!(event);
}
